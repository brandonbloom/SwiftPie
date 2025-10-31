import Foundation
import HTTPTypes
import NIOHTTP1
import SwiftPie

private struct PeerResponderInput {
    var method: HTTPRequest.Method
    var path: String
    var target: String
    var queryParameters: [String: [String]]
    var headers: [String: [String]]
    var headerStorage: [(name: String, value: String)]
    var body: Data
    var scheme: String?
    var host: String?

    init(
        method: HTTPRequest.Method,
        path: String,
        queryParameters: [String: [String]],
        headers: [String: [String]],
        headerStorage: [(name: String, value: String)],
        body: Data,
        scheme: String?,
        host: String?
    ) {
        self.method = method
        self.path = path
        self.target = path
        self.queryParameters = queryParameters
        self.headers = headers
        self.headerStorage = headerStorage
        self.body = body
        self.scheme = scheme
        self.host = host
    }

    init(capturedRequest: CapturedRequest, head: HTTPRequestHead, baseURL: URL?) {
        self.method = HTTPRequest.Method(rawValue: head.method.rawValue) ?? .get
        self.path = capturedRequest.path
        self.target = capturedRequest.uri
        self.queryParameters = capturedRequest.queryParameters
        self.headers = capturedRequest.headers.reduce(into: [:]) { partialResult, header in
            partialResult[header.name.lowercased(), default: []].append(header.value)
        }
        self.headerStorage = capturedRequest.headers.map { ($0.name, $0.value) }
        self.body = capturedRequest.body
        self.scheme = baseURL?.scheme ?? "http"
        self.host = baseURL?.host
    }

    init(peerRequest: PeerRequest) {
        let request = peerRequest.request
        self.method = request.method
        let pathAndQuery = request.path ?? "/"
        let parsed = Self.splitPathAndQuery(from: pathAndQuery)
        self.path = parsed.path
        self.target = pathAndQuery
        self.queryParameters = parsed.queryParameters
        var lowered: [String: [String]] = [:]
        var storage: [(String, String)] = []
        for field in request.headerFields {
            storage.append((field.name.rawName, field.value))
            lowered[field.name.rawName.lowercased(), default: []].append(field.value)
        }
        self.headers = lowered
        self.headerStorage = storage
        self.body = peerRequest.body.data ?? Data()
        self.scheme = request.scheme
        if let authority = request.authority {
            self.host = authority
        } else {
            self.host = nil
        }
    }

    private static func splitPathAndQuery(from pathAndQuery: String) -> (path: String, queryParameters: [String: [String]]) {
        guard let questionMarkIndex = pathAndQuery.firstIndex(of: "?") else {
            return (pathAndQuery, [:])
        }

        let path = String(pathAndQuery[..<questionMarkIndex])
        let queryString = pathAndQuery[pathAndQuery.index(after: questionMarkIndex)...]
        var components = URLComponents()
        components.query = String(queryString)

        let queryParameters = components.queryItems?.reduce(into: [:], { partialResult, item in
            partialResult[item.name, default: []].append(item.value ?? "")
        }) ?? [:]

        return (path.isEmpty ? "/" : path, queryParameters)
    }

    var singleValueQuery: [String: String] {
        queryParameters.reduce(into: [:]) { partialResult, entry in
            partialResult[entry.key] = entry.value.last ?? ""
        }
    }

    var headerDictionary: [String: String] {
        headerStorage.reduce(into: [:]) { result, entry in
            result[entry.name] = entry.value
        }
    }

    var cookies: [String: String] {
        guard let cookieHeader = headers["cookie"]?.last else {
            return [:]
        }

        return cookieHeader
            .split(separator: ";")
            .reduce(into: [:]) { partialResult, pair in
                let parts = pair.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }

                guard parts.count == 2 else { return }
                partialResult[parts[0]] = parts[1]
            }
    }

    var formPayload: [String: String] {
        guard let string = String(data: body, encoding: .utf8) else {
            return [:]
        }
        return string
            .split(separator: "&")
            .reduce(into: [:]) { result, pair in
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return }
                let name = parts[0].removingPercentEncoding ?? parts[0]
                let value = parts[1].removingPercentEncoding ?? parts[1]
                result[name] = value
            }
    }

    func fullURL(baseURL: URL?) -> String {
        if let scheme, let host {
            return "\(scheme)://\(host)\(target)"
        }

        if let baseURL,
           let absolute = URL(string: target, relativeTo: baseURL)?.absoluteString {
            return absolute
        }

        return target
    }

    func headerValues(for name: String) -> [String] {
        headers[name.lowercased()] ?? []
    }
}

public enum TestPeerResponder {
    public static func makePeerResponder(baseURL: URL? = nil) -> PeerResponder {
        return { request in
            let input = PeerResponderInput(peerRequest: request)
            return respond(to: input, baseURL: baseURL)
        }
    }

    static func respond(to captured: CapturedRequest, head: HTTPRequestHead, baseURL: URL) -> ResponsePayload {
        let input = PeerResponderInput(capturedRequest: captured, head: head, baseURL: baseURL)
        return respond(to: input, baseURL: baseURL)
    }

    private static func respond(to input: PeerResponderInput, baseURL: URL?) -> ResponsePayload {
        switch input.path {
        case "/get":
            return makeGetResponse(for: input, baseURL: baseURL)
        case "/post":
            return makePostResponse(for: input, baseURL: baseURL)
        case "/headers":
            return makeHeadersResponse(for: input)
        case "/cookies":
            return makeCookiesResponse(for: input)
        case "/cookies/set":
            return makeSetCookiesResponse(for: input)
        default:
            if input.path.hasPrefix("/status/"),
               let response = makeStatusResponse(for: input) {
                return response
            }

            if input.path == "/redirect-to",
               let response = makeRedirectToResponse(for: input) {
                return response
            }

            if input.path.hasPrefix("/redirect/"),
               let response = makeRedirectLoopResponse(for: input) {
                return response
            }

            return makeNotFoundResponse(for: input)
        }
    }

    private static func makeGetResponse(for input: PeerResponderInput, baseURL: URL?) -> ResponsePayload {
        let object: [String: Any] = [
            "args": input.singleValueQuery,
            "headers": input.headerDictionary,
            "url": input.fullURL(baseURL: baseURL),
        ]
        return jsonResponse(object: object)
    }

    private static func makePostResponse(for input: PeerResponderInput, baseURL: URL?) -> ResponsePayload {
        let contentType = input.headerValues(for: "content-type").last?.lowercased() ?? ""
        let rawBody = String(data: input.body, encoding: .utf8) ?? ""

        var jsonPayload: Any?
        var formPayload: [String: String] = [:]

        if contentType.contains("application/json") {
            jsonPayload = try? JSONSerialization.jsonObject(with: input.body, options: [])
        } else if contentType.contains("application/x-www-form-urlencoded") {
            formPayload = input.formPayload
        }

        var object: [String: Any] = [
            "args": input.singleValueQuery,
            "headers": input.headerDictionary,
            "data": rawBody,
            "url": input.fullURL(baseURL: baseURL),
        ]

        if let jsonPayload {
            object["json"] = jsonPayload
        } else {
            object["json"] = NSNull()
        }

        if !formPayload.isEmpty {
            object["form"] = formPayload
        }

        return jsonResponse(object: object)
    }

    private static func makeHeadersResponse(for input: PeerResponderInput) -> ResponsePayload {
        jsonResponse(object: input.headerDictionary)
    }

    private static func makeStatusResponse(for input: PeerResponderInput) -> ResponsePayload? {
        let components = input.path.split(separator: "/")
        guard let last = components.last, let code = Int(last) else {
            return nil
        }

        let nioStatus = HTTPResponseStatus(statusCode: code)
        let status = HTTPResponse.Status(code: Int(nioStatus.code), reasonPhrase: nioStatus.reasonPhrase)
        let bodyText = input.queryParameters["body"]?.last ?? nioStatus.reasonPhrase
        return textResponse(bodyText, status: status)
    }

    private static func makeRedirectToResponse(for input: PeerResponderInput) -> ResponsePayload? {
        guard let target = input.queryParameters["url"]?.last,
              let location = URL(string: target) else {
            return nil
        }

        return redirectResponse(to: location.absoluteString)
    }

    private static func makeRedirectLoopResponse(for input: PeerResponderInput) -> ResponsePayload? {
        let components = input.path.split(separator: "/")
        guard components.count == 3, let iterations = Int(components[2]), iterations > 0 else {
            return nil
        }

        if iterations == 1 {
            let location = input.queryParameters["to"]?.last ?? "/get"
            return redirectResponse(to: location)
        } else {
            let next = "/redirect/\(iterations - 1)"
            return redirectResponse(to: next)
        }
    }

    private static func makeCookiesResponse(for input: PeerResponderInput) -> ResponsePayload {
        let object: [String: Any] = [
            "cookies": input.cookies
        ]
        return jsonResponse(object: object)
    }

    private static func makeSetCookiesResponse(for input: PeerResponderInput) -> ResponsePayload {
        var fields = HTTPFields()
        if let name = HTTPField.Name("Set-Cookie") {
            for (cookieName, values) in input.queryParameters {
                for value in values {
                    fields.append(HTTPField(name: name, value: "\(cookieName)=\(value)"))
                }
            }
        }

        let response = HTTPResponse(status: .ok, headerFields: fields)
        return ResponsePayload(response: response, body: .none)
    }

    private static func makeNotFoundResponse(for input: PeerResponderInput) -> ResponsePayload {
        jsonResponse(
            object: ["error": "not_found", "path": input.path],
            status: .notFound
        )
    }

    private static func jsonResponse(object: Any, status: HTTPResponse.Status = .ok) -> ResponsePayload {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        let text = String(data: data, encoding: .utf8) ?? "{}"

        var fields = HTTPFields()
        if let contentType = HTTPField.Name("Content-Type") {
            fields.append(HTTPField(name: contentType, value: "application/json"))
        }

        let response = HTTPResponse(status: status, headerFields: fields)
        return ResponsePayload(response: response, body: .text(text))
    }

    private static func textResponse(_ text: String, status: HTTPResponse.Status) -> ResponsePayload {
        var fields = HTTPFields()
        if let contentType = HTTPField.Name("Content-Type") {
            fields.append(HTTPField(name: contentType, value: "text/plain; charset=utf-8"))
        }
        let response = HTTPResponse(status: status, headerFields: fields)
        return ResponsePayload(response: response, body: .text(text))
    }

    private static func redirectResponse(to location: String) -> ResponsePayload {
        var fields = HTTPFields()
        if let locationName = HTTPField.Name("Location") {
            fields.append(HTTPField(name: locationName, value: location))
        }

        let response = HTTPResponse(status: .found, headerFields: fields)
        return ResponsePayload(response: response, body: .none)
    }
}
