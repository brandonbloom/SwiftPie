import Foundation
import HTTPTypes

enum RequestBuilder {
    static func build(from parsed: ParsedRequest) throws -> RequestPayload {
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

        for header in parsed.items.headers {
            guard let name = HTTPField.Name(header.name) else {
                throw RequestBuilderError.invalidHeaderName(header.name)
            }

            switch header.value {
            case .some(let value):
                headers.append(HTTPField(name: name, value: value))
            case .none:
                headerRemovals.append(name)
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
            data: parsed.items.data,
            files: parsed.items.files,
            headerRemovals: headerRemovals
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
}

enum RequestBuilderError: Error, Equatable {
    case invalidMethod(String)
    case unsupportedURL(URL)
    case invalidHeaderName(String)
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
        }
    }
}

public struct RequestPayload: Equatable {
    public var request: HTTPRequest
    public var data: [DataField]
    public var files: [FileField]
    public var headerRemovals: [HTTPField.Name]

    public init(
        request: HTTPRequest,
        data: [DataField],
        files: [FileField],
        headerRemovals: [HTTPField.Name]
    ) {
        self.request = request
        self.data = data
        self.files = files
        self.headerRemovals = headerRemovals
    }
}
