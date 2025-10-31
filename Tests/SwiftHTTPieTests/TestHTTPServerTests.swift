import Foundation
import Testing
import SwiftHTTPieTestSupport

@Suite("NIO HTTP test server")
struct NIOHTTPTestServerTests {
    @Test("GET /get echoes query params and headers")
    func getEndpointEchoesArguments() async throws {
        try await withTestServer { server in
            var components = URLComponents(url: server.baseURL.appendingPathComponent("get"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "foo", value: "bar"),
                URLQueryItem(name: "bar", value: "baz")
            ]

            var request = URLRequest(url: try #require(components.url))
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)

            #expect((response as? HTTPURLResponse)?.statusCode == 200)

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let args = json?["args"] as? [String: String]
            let headers = json?["headers"] as? [String: String]

            #expect(args?["foo"] == "bar")
            #expect(headers?["Accept"] == "application/json")

            let recorded = try #require(server.lastRequest(path: "/get"))
            #expect(recorded.queryParameters["foo"] == ["bar"])
            #expect(recorded.headerValues(for: "accept") == ["application/json"])
        }
    }

    @Test("POST /post echoes JSON payloads")
    func postEndpointEchoesJSON() async throws {
        try await withTestServer { server in
            let url = server.baseURL.appendingPathComponent("post")

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let payload = ["hello": "world", "flag": true] as [String: Any]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await URLSession.shared.data(for: request)

            #expect((response as? HTTPURLResponse)?.statusCode == 200)

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let jsonEcho = json?["json"] as? [String: Any]

            #expect(jsonEcho?["hello"] as? String == "world")
            #expect(jsonEcho?["flag"] as? Bool == true)

            let recorded = try #require(server.lastRequest(path: "/post"))
            #expect(String(data: recorded.body, encoding: .utf8)?.contains("\"hello\":\"world\"") == true)
        }
    }

    @Test("Status endpoints emit configured response codes")
    func statusEndpointProducesCodes() async throws {
        try await withTestServer { server in
            let url = server.baseURL.appendingPathComponent("status/404")
            let (data, response) = try await URLSession.shared.data(from: url)

            let httpResponse = try #require(response as? HTTPURLResponse)
            #expect(httpResponse.statusCode == 404)

            let body = String(data: data, encoding: .utf8)
            #expect(body?.contains("Not Found") == true)
        }
    }

    @Test("Set-Cookie endpoint issues cookies in headers")
    func setCookiesEndpointIssuesHeaders() async throws {
        try await withTestServer { server in
            var components = URLComponents(url: server.baseURL.appendingPathComponent("cookies/set"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "session", value: "abc123"),
                URLQueryItem(name: "mode", value: "debug")
            ]

            let url = try #require(components.url)
            let (_, response) = try await URLSession.shared.data(from: url)

            let httpResponse = try #require(response as? HTTPURLResponse)
            let cookies = httpResponse.value(forHTTPHeaderField: "Set-Cookie") ?? ""

            #expect(cookies.contains("session=abc123"))
            #expect(cookies.contains("mode=debug"))
        }
    }

    @Test("Redirect endpoint returns Location header")
    func redirectEndpointIssuesLocation() async throws {
        try await withTestServer { server in
            var components = URLComponents(url: server.baseURL.appendingPathComponent("redirect-to"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "url", value: server.baseURL.appendingPathComponent("get").absoluteString)
            ]

            var request = URLRequest(url: try #require(components.url))
            request.httpMethod = "GET"

            let delegate = RedirectCollector()
            let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
            defer { session.invalidateAndCancel() }

            let (_, response) = try await session.data(for: request)

            let httpResponse = try #require(response as? HTTPURLResponse)
            #expect(httpResponse.statusCode == 302)
            #expect(httpResponse.value(forHTTPHeaderField: "Location")?.hasSuffix("/get") == true)
        }
    }
}

private final class RedirectCollector: NSObject, URLSessionTaskDelegate {
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
