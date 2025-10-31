import Foundation
import HTTPTypes

public final class URLSessionTransport: RequestTransport {
    private let session: URLSession
    private let defaultTimeout: TimeInterval

    public init(configuration: URLSessionConfiguration = .ephemeral) {
        let baseConfiguration = (configuration.copy() as? URLSessionConfiguration) ?? configuration
        let config = baseConfiguration
        config.waitsForConnectivity = false
        config.httpShouldUsePipelining = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.httpAdditionalHeaders = [:]

        if config.timeoutIntervalForRequest <= 0 {
            config.timeoutIntervalForRequest = 60
        }

        self.session = URLSession(configuration: config)
        self.defaultTimeout = config.timeoutIntervalForRequest
    }

    deinit {
        session.invalidateAndCancel()
    }

    public func send(_ payload: RequestPayload) throws -> ResponsePayload {
        let request = try makeURLRequest(from: payload)
        let (data, response) = try performRequest(request)
        return try makeResponse(from: data, response: response)
    }

    private func makeURLRequest(from payload: RequestPayload) throws -> URLRequest {
        guard
            let scheme = payload.request.scheme,
            let authority = payload.request.authority
        else {
            throw TransportError.internalFailure("missing scheme or authority in request payload")
        }

        let path = payload.request.path ?? "/"
        guard let url = URL(string: "\(scheme)://\(authority)\(path)") else {
            throw TransportError.internalFailure("unable to build URL for request '\(scheme)://\(authority)\(path)'")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = defaultTimeout
        request.httpMethod = payload.request.method.rawValue

        for field in payload.request.headerFields {
            request.addValue(field.value, forHTTPHeaderField: field.name.rawName)
        }

        if let body = try encodeBody(from: payload) {
            request.httpBody = body.data

            if let contentType = body.contentType,
               shouldApplyDefaultHeader(named: "Content-Type", for: payload) {
                request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
        }

        return request
    }

    private func encodeBody(from payload: RequestPayload) throws -> EncodedBody? {
        if payload.data.isEmpty, payload.files.isEmpty {
            return nil
        }

        if !payload.files.isEmpty {
            return try encodeMultipartBody(from: payload)
        }

        if payload.data.contains(where: { if case .json = $0.value { return true } else { return false } }) {
            return try encodeJSONBody(from: payload.data)
        }

        return encodeFormBody(from: payload.data)
    }

    private func encodeMultipartBody(from payload: RequestPayload) throws -> EncodedBody {
        let boundary = "boundary-\(UUID().uuidString)"
        var body = Data()

        func append(_ string: String) {
            guard let data = string.data(using: .utf8) else { return }
            body.append(data)
        }

        for dataField in payload.data {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(escapeMultipartFieldName(dataField.name))\"\r\n")
            append("\r\n")

            let valueString: String
            switch dataField.value {
            case .text(let text):
                valueString = text
            case .json(let json):
                valueString = try json.asJSONString()
            }

            append("\(valueString)\r\n")
        }

        for fileField in payload.files {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(escapeMultipartFieldName(fileField.name))\"; filename=\"\(fileField.path.lastPathComponent)\"\r\n")
            append("Content-Type: application/octet-stream\r\n")
            append("\r\n")

            let fileData: Data
            do {
                fileData = try Data(contentsOf: fileField.path)
            } catch {
                throw TransportError.internalFailure("failed to read file '\(fileField.path.path)': \(error.localizedDescription)")
            }

            body.append(fileData)
            append("\r\n")
        }

        append("--\(boundary)--\r\n")

        return EncodedBody(
            data: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
    }

    private func encodeJSONBody(from fields: [DataField]) throws -> EncodedBody {
        var object: [String: Any] = [:]

        for field in fields {
            let value: Any
            switch field.value {
            case .text(let string):
                value = string
            case .json(let json):
                value = try json.toJSONObject()
            }

            if let existing = object[field.name] {
                if var array = existing as? [Any] {
                    array.append(value)
                    object[field.name] = array
                } else {
                    object[field.name] = [existing, value]
                }
            } else {
                object[field.name] = value
            }
        }

        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return EncodedBody(data: data, contentType: "application/json")
    }

    private func encodeFormBody(from fields: [DataField]) -> EncodedBody {
        let components = fields.map { field -> String in
            let encodedName = field.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? field.name
            let encodedValue: String
            switch field.value {
            case .text(let string):
                encodedValue = string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? string
            case .json(let json):
                let jsonString = (try? json.asJSONString()) ?? ""
                encodedValue = jsonString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? jsonString
            }
            return "\(encodedName)=\(encodedValue)"
        }

        let formString = components.joined(separator: "&")
        let data = formString.data(using: .utf8) ?? Data()
        return EncodedBody(
            data: data,
            contentType: "application/x-www-form-urlencoded; charset=utf-8"
        )
    }

    private func shouldApplyDefaultHeader(named name: String, for payload: RequestPayload) -> Bool {
        guard let fieldName = HTTPField.Name(name) else {
            return true
        }

        if payload.headerRemovals.contains(fieldName) {
            return false
        }

        for field in payload.request.headerFields where field.name == fieldName {
            return false
        }

        return true
    }

    private func performRequest(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        /// Box bridging the async completion handler onto this synchronous API.
        /// The value is only written once before the semaphore is signalled,
        /// so it is safe to treat as `Sendable`.
        final class ResultBox: @unchecked Sendable {
            var value: Result<(Data, HTTPURLResponse), Error>?
        }

        let semaphore = DispatchSemaphore(value: 0)
        let result = ResultBox()

        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }

            if let error {
                result.value = .failure(error)
                return
            }

            guard let data, let httpResponse = response as? HTTPURLResponse else {
                result.value = .failure(TransportError.internalFailure("missing HTTP response"))
                return
            }

            result.value = .success((data, httpResponse))
        }

        task.resume()

        let timeoutInterval = request.timeoutInterval > 0 ? request.timeoutInterval : defaultTimeout

        if semaphore.wait(timeout: .now() + timeoutInterval) == .timedOut {
            task.cancel()
            throw TransportError.networkError("request timed out after \(Int(timeoutInterval))s")
        }

        guard let finalResult = result.value else {
            throw TransportError.internalFailure("request cancelled")
        }

        switch finalResult {
        case .success(let success):
            return success
        case .failure(let error):
            throw mapError(error)
        }
    }

    private func makeResponse(from data: Data, response: HTTPURLResponse) throws -> ResponsePayload {
        var fields = HTTPFields()
        for (key, value) in response.allHeaderFields {
            guard let name = key as? String,
                  let headerName = HTTPField.Name(name) else {
                continue
            }

            let stringValue: String
            if let string = value as? String {
                stringValue = string
            } else if let number = value as? NSNumber {
                stringValue = number.stringValue
            } else {
                continue
            }

            fields.append(HTTPField(name: headerName, value: stringValue))
        }

        let status = HTTPResponse.Status(code: response.statusCode)
        let httpResponse = HTTPResponse(
            status: status,
            headerFields: fields
        )

        let body = makeResponseBody(from: data, response: response)
        return ResponsePayload(response: httpResponse, body: body)
    }

    private func makeResponseBody(from data: Data, response: HTTPURLResponse) -> ResponseBody {
        guard !data.isEmpty else {
            return .none
        }

        if let string = decodeTextBody(data, response: response) {
            return .text(string)
        }

        return .data(data)
    }

    private func decodeTextBody(_ data: Data, response: HTTPURLResponse) -> String? {
        if let encoding = response.stringEncoding {
            return String(data: data, encoding: encoding)
        }

        if isTextual(mimeType: response.mimeType) {
            if let string = String(data: data, encoding: .utf8) {
                return string
            }

            if let string = String(data: data, encoding: .isoLatin1) {
                return string
            }
        }

        return nil
    }

    private func mapError(_ error: Error) -> TransportError {
        if let transportError = error as? TransportError {
            return transportError
        }

        if let urlError = error as? URLError {
            return TransportError.networkError(urlError.localizedDescription)
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return TransportError.networkError(nsError.localizedDescription)
        }

        return TransportError.internalFailure(error.localizedDescription)
    }

    private func isTextual(mimeType: String?) -> Bool {
        guard let mimeType else { return true }

        let lowercased = mimeType.lowercased()

        if lowercased.hasPrefix("text/") {
            return true
        }

        if lowercased == "application/json" ||
            lowercased.hasSuffix("+json") ||
            lowercased == "application/xml" ||
            lowercased.hasSuffix("+xml") ||
            lowercased == "application/x-www-form-urlencoded" {
            return true
        }

        return false
    }

    private func escapeMultipartFieldName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "\"", with: "%22")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

}

private struct EncodedBody {
    var data: Data
    var contentType: String?
}

private extension HTTPURLResponse {
    var stringEncoding: String.Encoding? {
        guard let encodingName = textEncodingName else {
            return nil
        }

        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(encodingName as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else {
            return nil
        }

        let rawValue = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: rawValue)
    }
}

private extension JSONValue {
    func toJSONObject() throws -> Any {
        switch self {
        case .string(let string):
            return string
        case .number(let number):
            return number
        case .bool(let value):
            return value
        case .null:
            return NSNull()
        case .array(let values):
            return try values.map { try $0.toJSONObject() }
        case .object(let dictionary):
            var result: [String: Any] = [:]
            for (key, value) in dictionary {
                result[key] = try value.toJSONObject()
            }
            return result
        }
    }

    func asJSONString() throws -> String {
        let object = try toJSONObject()
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? ""
    }
}
