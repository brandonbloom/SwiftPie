import HTTPTypes
import Testing
@testable import SwiftHTTPie

@Suite("Request builder")
struct RequestBuilderTests {
    @Test("Produces an HTTP request with merged data and headers")
    func buildsHTTPRequest() throws {
        let parsed = try RequestParser.parse(arguments: [
            "POST",
            "https://user:pass@example.com:8443/resource?existing=1",
            "Header:one",
            "Header:two",
            "Unset-Header:",
            "payload=value",
            "json:=true"
        ])

        let payload = try RequestBuilder.build(from: parsed)

        #expect(payload.request.method.rawValue == "POST")
        #expect(payload.request.scheme == "https")
        #expect(payload.request.authority == "user:pass@example.com:8443")
        #expect(payload.request.path == "/resource?existing=1")

        let headerName = try #require(HTTPField.Name("Header"))
        let headerValues = payload.request.headerFields[values: headerName]
        #expect(headerValues == ["one", "two"])

        let unsetHeader = try #require(HTTPField.Name("Unset-Header"))
        #expect(payload.headerRemovals.contains(unsetHeader))

        #expect(payload.data == [
            DataField(name: "payload", value: .text("value")),
            DataField(name: "json", value: .json(.bool(true)))
        ])

        #expect(payload.files.isEmpty)
    }

    @Test("Formats IPv6 authority with brackets")
    func formatsIPv6Host() throws {
        let parsed = try RequestParser.parse(arguments: [
            "GET",
            "http://[::1]:8080/example"
        ])

        let payload = try RequestBuilder.build(from: parsed)

        #expect(payload.request.authority == "[::1]:8080")
        #expect(payload.request.path == "/example")
    }
}
