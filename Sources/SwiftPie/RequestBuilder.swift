import Foundation
import HTTPTypes

enum RequestBuilder {
    static func build(
        from parsed: ParsedRequest,
        bodyMode: RequestPayload.BodyMode = .json,
        rawBody: RequestPayload.RawBody? = nil
    ) throws -> RequestPayload {
        let url = parsed.url

        guard let method = HTTPRequest.Method(parsed.method.rawValue) else {
            throw RequestBuilderError.invalidMethod(parsed.method.rawValue)
        }

        guard let scheme = url.scheme, !scheme.isEmpty,
              let host = url.host, !host.isEmpty
        else {
            throw RequestBuilderError.unsupportedURL(url)
        }

        let authority = makeAuthority(for: url, host: host)
        let path = makePath(from: url)

        var headers = HTTPFields()
        var headerRemovals: [HTTPField.Name] = []
        var resolvedData: [DataField] = []

        for header in parsed.items.headers {
            guard let name = HTTPField.Name(header.name) else {
                throw RequestBuilderError.invalidHeaderName(header.name)
            }

            switch header.value {
            case .some(let value):
                headers.append(HTTPField(name: name, value: value))
            case .none:
                headerRemovals.append(name)
            case .file(let url):
                let value = try loadTextFile(at: url, description: header.name)
                headers.append(HTTPField(name: name, value: value))
            case .stdin:
                throw RequestBuilderError.stdinUnavailable("header '\(header.name)'")
            }
        }

        for field in parsed.items.data {
            let resolvedValue: DataValue
            switch field.value {
            case .text, .json:
                resolvedValue = field.value
            case .textFile(let url):
                let contents = try loadTextFile(at: url, description: field.name)
                resolvedValue = .text(contents)
            case .jsonFile(let url):
                let contents: Data
                do {
                    contents = try Data(contentsOf: url)
                } catch {
                    throw RequestBuilderError.fileReadFailed(
                        url: url,
                        reason: "failed to read field '\(field.name)': \(error.localizedDescription)"
                    )
                }
                let json = try JSONValue.parse(from: contents)
                resolvedValue = .json(json)
            case .textStdin:
                throw RequestBuilderError.stdinUnavailable("field '\(field.name)'")
            case .jsonStdin:
                throw RequestBuilderError.stdinUnavailable("field '\(field.name)'")
            }

            resolvedData.append(DataField(name: field.name, value: resolvedValue))
        }

        if bodyMode == .form {
            for field in resolvedData where field.value.containsJSONValue {
                throw RequestBuilderError.jsonNotAllowedInForm(field.name)
            }
        }

        if !parsed.items.files.isEmpty, bodyMode != .form {
            throw RequestBuilderError.fileUploadsRequireForm
        }

        if bodyMode == .raw {
            guard rawBody != nil else {
                throw RequestBuilderError.missingRawBody
            }

            if !resolvedData.isEmpty || !parsed.items.files.isEmpty {
                throw RequestBuilderError.rawBodyConflictsWithItems
            }
        }

        let request = HTTPRequest(
            method: method,
            scheme: scheme,
            authority: authority,
            path: path,
            headerFields: headers
        )

        return RequestPayload(
            request: request,
            data: resolvedData,
            files: parsed.items.files,
            headerRemovals: headerRemovals,
            bodyMode: bodyMode,
            rawBody: rawBody
        )
    }

    private static func makeAuthority(for url: URL, host: String) -> String {
        let formattedHost: String = {
            if host.contains(":"), !host.hasPrefix("["), !host.hasSuffix("]") {
                return "[\(host)]"
            }
            return host
        }()

        let credentials: String? = {
            guard let user = url.user else {
                return nil
            }

            if let password = url.password {
                return "\(user):\(password)"
            }
            return user
        }()

        let hostPortion: String
        if let port = url.port {
            hostPortion = "\(formattedHost):\(port)"
        } else {
            hostPortion = formattedHost
        }

        if let credentials {
            return "\(credentials)@\(hostPortion)"
        }
        return hostPortion
    }

    private static func makePath(from url: URL) -> String {
        var path = url.path.isEmpty ? "/" : url.path
        if let query = url.query, !query.isEmpty {
            path.append("?")
            path.append(query)
        }
        return path
    }

    private static func loadTextFile(at url: URL, description: String) throws -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw RequestBuilderError.fileReadFailed(
                url: url,
                reason: "failed to read \(description): \(error.localizedDescription)"
            )
        }
    }
}

enum RequestBuilderError: Error, Equatable {
    case invalidMethod(String)
    case unsupportedURL(URL)
    case invalidHeaderName(String)
    case fileReadFailed(url: URL, reason: String)
    case stdinUnavailable(String)
    case jsonNotAllowedInForm(String)
    case fileUploadsRequireForm
    case missingRawBody
    case rawBodyConflictsWithItems
}

extension RequestBuilderError {
    var cliDescription: String {
        switch self {
        case .invalidMethod(let method):
            return "unsupported HTTP method '\(method)'"
        case .unsupportedURL(let url):
            return "unsupported URL '\(url.absoluteString)'"
        case .invalidHeaderName(let name):
            return "invalid header name '\(name)'"
        case .fileReadFailed(let url, let reason):
            return "\(reason) (\(url.path))"
        case .stdinUnavailable(let context):
            return "\(context) requires stdin input, but it was not provided"
        case .jsonNotAllowedInForm(let name):
            return "field '\(name)' uses JSON data which is not allowed with --form"
        case .fileUploadsRequireForm:
            return "file uploads require --form"
        case .missingRawBody:
            return "--raw requires a request body value"
        case .rawBodyConflictsWithItems:
            return "cannot mix --raw with request items"
        }
    }
}

public struct RequestPayload: Equatable {
    public enum BodyMode: Equatable {
        case json
        case form
        case raw
    }

    public enum RawBody: Equatable {
        case inline(String)
        case data(Data)
    }

    public var request: HTTPRequest
    public var data: [DataField]
    public var files: [FileField]
    public var headerRemovals: [HTTPField.Name]
    public var bodyMode: BodyMode
    public var rawBody: RawBody?

    public init(
        request: HTTPRequest,
        data: [DataField],
        files: [FileField],
        headerRemovals: [HTTPField.Name],
        bodyMode: BodyMode = .json,
        rawBody: RawBody? = nil
    ) {
        self.request = request
        self.data = data
        self.files = files
        self.headerRemovals = headerRemovals
        self.bodyMode = bodyMode
        self.rawBody = rawBody
    }
}

private extension DataValue {
    var containsJSONValue: Bool {
        if case .json = self {
            return true
        }
        return false
    }
}
