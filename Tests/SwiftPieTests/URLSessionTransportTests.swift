#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Foundation
import Testing
import SwiftPieTestSupport
@testable import SwiftPie

@Suite("URLSession transport")
struct URLSessionTransportTests {
    @Test("Performs GET requests and returns the response payload")
    func performsGETRequests() throws {
        try withTestServer { server in
            let transport = URLSessionTransport()
            let parsed = try RequestParser.parse(arguments: [
                server.baseURL.appendingPathComponent("get").absoluteString,
                "Accept:application/json"
            ])

            let payload = try RequestBuilder.build(from: parsed)
            let response = try transport.send(payload, options: TransportOptions())

            #expect(response.response.status == .ok)

            guard case .text(let body) = response.body else {
                Issue.record("Expected text response body, got \(response.body)")
                return
            }

            #expect(body.contains("\"url\""))

            let recorded = try #require(server.lastRequest(path: "/get"))
            #expect(recorded.headerValues(for: "Accept") == ["application/json"])
        }
    }

    @Test("Encodes JSON by default when only text fields are provided")
    func encodesJSONByDefault() throws {
        try withTestServer { server in
            let transport = URLSessionTransport()
            let parsed = try RequestParser.parse(arguments: [
                "POST",
                server.baseURL.appendingPathComponent("post").absoluteString,
                "foo=bar",
                "baz=qux"
            ])

            let payload = try RequestBuilder.build(from: parsed)
            let response = try transport.send(payload, options: TransportOptions())

            guard case .text(let text) = response.body else {
                Issue.record("Expected text response body, got \(response.body)")
                return
            }

            #expect(text.contains("\"json\""))

            let recorded = try #require(server.lastRequest(path: "/post"))
            let contentTypes = recorded.headerValues(for: "Content-Type")
            #expect(contentTypes.last == "application/json")
            let bodyString = String(data: recorded.body, encoding: .utf8)
            #expect(bodyString?.contains("\"foo\":\"bar\"") == true)
            #expect(bodyString?.contains("\"baz\":\"qux\"") == true)
        }
    }

    @Test("Encodes form data when --form is requested")
    func encodesFormDataWithFormMode() throws {
        try withTestServer { server in
            let transport = URLSessionTransport()
            let parsed = try RequestParser.parse(arguments: [
                "POST",
                server.baseURL.appendingPathComponent("post").absoluteString,
                "foo=bar",
                "baz=qux"
            ])

            let payload = try RequestBuilder.build(from: parsed, bodyMode: .form)
            _ = try transport.send(payload, options: TransportOptions())

            let recorded = try #require(server.lastRequest(path: "/post"))
            let contentTypes = recorded.headerValues(for: "Content-Type")
            #expect(contentTypes.last?.contains("application/x-www-form-urlencoded") == true)
            let bodyString = String(data: recorded.body, encoding: .utf8)
            #expect(bodyString == "foo=bar&baz=qux")
        }
    }

    @Test("Encodes raw bodies without additional processing")
    func encodesRawBodies() throws {
        try withTestServer { server in
            let transport = URLSessionTransport()
            let parsed = try RequestParser.parse(arguments: [
                "POST",
                server.baseURL.appendingPathComponent("post").absoluteString
            ])

            let payload = try RequestBuilder.build(
                from: parsed,
                bodyMode: .raw,
                rawBody: .inline("raw-body")
            )

            _ = try transport.send(payload, options: TransportOptions())

            let recorded = try #require(server.lastRequest(path: "/post"))
            let contentTypes = recorded.headerValues(for: "Content-Type")
            if let contentType = contentTypes.last {
                #expect(contentType.contains("application/json") == false)
                #expect(contentType.contains("multipart/form-data") == false)
            }
            let bodyString = String(data: recorded.body, encoding: .utf8)
            #expect(bodyString == "raw-body")
        }
    }

    @Test("Encodes JSON when JSON fields are present")
    func encodesJSONBodies() throws {
        try withTestServer { server in
            let transport = URLSessionTransport()
            let parsed = try RequestParser.parse(arguments: [
                "POST",
                server.baseURL.appendingPathComponent("post").absoluteString,
                "flag:=true",
                "message=hello"
            ])

            let payload = try RequestBuilder.build(from: parsed)
            let response = try transport.send(payload, options: TransportOptions())

            guard case .text(let text) = response.body else {
                Issue.record("Expected text response body, got \(response.body)")
                return
            }

            #expect(text.contains("\"json\""))

            let recorded = try #require(server.lastRequest(path: "/post"))
            let contentTypes = recorded.headerValues(for: "Content-Type")
            #expect(contentTypes.last == "application/json")

            let bodyString = String(data: recorded.body, encoding: .utf8)
            #expect(bodyString?.contains("\"flag\":true") == true)
            #expect(bodyString?.contains("\"message\":\"hello\"") == true)
        }
    }

    @Test("Propagates lower-level errors as network transport failures")
    func propagatesNetworkErrors() throws {
        let transport = URLSessionTransport()
        let parsed = try RequestParser.parse(arguments: [
            "http://127.0.0.1:1"
        ])
        let payload = try RequestBuilder.build(from: parsed)

        do {
            _ = try transport.send(payload, options: TransportOptions())
            Issue.record("Expected network error")
        } catch let error as TransportError {
            switch error {
            case .networkError(let message):
                #expect(message.isEmpty == false)
            default:
                Issue.record("Expected network error, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
