#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CoreFoundation)
import CoreFoundation
#endif
import Foundation
import HTTPTypes

public final class URLSessionTransport: RequestTransport {
    private let baseConfiguration: URLSessionConfiguration
    private let secureSession: URLSession
    private let secureDelegate: SecureSessionDelegate
#if canImport(Darwin)
    private var insecureSession: URLSession?
    private var insecureDelegate: InsecureSessionDelegate?
#endif
    private let defaultTimeout: TimeInterval
#if canImport(Darwin)
    private let sessionLock = NSLock()
#endif

    public init(configuration: URLSessionConfiguration = .ephemeral) {
        let baseConfiguration = (configuration.copy() as? URLSessionConfiguration) ?? configuration
        let config = baseConfiguration
#if canImport(Darwin)
        config.waitsForConnectivity = false
#endif
#if canImport(Darwin)
        config.httpShouldUsePipelining = true
#endif
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.httpAdditionalHeaders = [:]

        if config.timeoutIntervalForRequest <= 0 {
            config.timeoutIntervalForRequest = 60
        }

        self.baseConfiguration = config
        self.secureDelegate = SecureSessionDelegate()
        self.secureSession = URLSession(configuration: config, delegate: secureDelegate, delegateQueue: nil)
        self.defaultTimeout = config.timeoutIntervalForRequest
    }

    deinit {
        secureSession.invalidateAndCancel()
#if canImport(Darwin)
        insecureSession?.invalidateAndCancel()
#endif
    }

    public func send(_ payload: RequestPayload, options: TransportOptions) throws -> ResponsePayload {
        let request = try makeURLRequest(from: payload, options: options)
        let session = session(for: options.verify)
        let (data, response) = try performRequest(request, session: session)
        return try makeResponse(from: data, response: response)
    }

    private func makeURLRequest(
        from payload: RequestPayload,
        options: TransportOptions
    ) throws -> URLRequest {
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
        request.timeoutInterval = options.timeout ?? defaultTimeout
        request.httpMethod = payload.request.method.rawValue

        for field in payload.request.headerFields {
            request.addValue(field.value, forHTTPHeaderField: field.name.rawName)
        }

        if let body = try RequestPayloadEncoding.encodeBody(from: payload) {
            request.httpBody = body.data

            if let contentType = body.contentType,
               let fieldName = HTTPField.Name("Content-Type"),
               RequestPayloadEncoding.shouldApplyDefaultHeader(named: fieldName, for: payload) {
                request.setValue(contentType, forHTTPHeaderField: fieldName.rawName)
            }
        }

        if payload.bodyMode == .raw,
           let fieldName = HTTPField.Name("Content-Type"),
           RequestPayloadEncoding.shouldApplyDefaultHeader(named: fieldName, for: payload) {
            request.setValue(nil, forHTTPHeaderField: fieldName.rawName)
        }

        if options.httpVersionPreference == .http1Only,
           let fieldName = HTTPField.Name("Connection"),
           RequestPayloadEncoding.shouldApplyDefaultHeader(named: fieldName, for: payload) {
            request.setValue("close", forHTTPHeaderField: "Connection")
        }

        return request
    }

    private func session(for verification: TransportOptions.TLSVerification) -> URLSession {
        switch verification {
        case .enforced:
            return secureSession
        case .disabled:
#if canImport(Darwin)
            sessionLock.lock()
            defer { sessionLock.unlock() }

            if let existing = insecureSession {
                return existing
            }

            let configuration = makeSessionConfiguration()
            let delegate = InsecureSessionDelegate()
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            insecureSession = session
            insecureDelegate = delegate
            return session
#else
            return secureSession
#endif
        }
    }

    private func makeSessionConfiguration() -> URLSessionConfiguration {
        (baseConfiguration.copy() as? URLSessionConfiguration) ?? baseConfiguration
    }

    private func performRequest(
        _ request: URLRequest,
        session: URLSession
    ) throws -> (Data, HTTPURLResponse) {
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

}

private final class SecureSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

#if canImport(Darwin)
private final class InsecureSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
#endif

private extension HTTPURLResponse {
    var stringEncoding: String.Encoding? {
#if canImport(Darwin)
        guard let encodingName = textEncodingName else {
            return nil
        }

        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(encodingName as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else {
            return nil
        }

        let rawValue = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: rawValue)
#else
        return nil
#endif
    }
}
