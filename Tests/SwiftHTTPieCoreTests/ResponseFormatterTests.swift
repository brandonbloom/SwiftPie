import HTTPTypes
import Testing
@testable import SwiftHTTPieCore

@Suite("Response formatter")
struct ResponseFormatterTests {
    @Test("Formats status line, headers, and body text")
    func formatsFullResponse() {
        var headers = HTTPFields()
        headers.append(HTTPField(name: HTTPField.Name("Content-Type")!, value: "application/json"))
        headers.append(HTTPField(name: HTTPField.Name("X-Custom")!, value: "value"))

        let response = ResponsePayload(
            response: HTTPResponse(status: .ok, headerFields: headers),
            body: .text("{\"message\":\"hello\"}")
        )

        let formatted = ResponseFormatter().format(response)

        #expect(formatted.contains("HTTP/1.1 200 OK"))
        #expect(formatted.contains("Content-Type: application/json"))
        #expect(formatted.contains("X-Custom: value"))
        #expect(formatted.contains("{\"message\":\"hello\"}"))
    }

    @Test("Omits body section when response body is empty")
    func omitsBodyWhenEmpty() {
        let response = ResponsePayload(
            response: HTTPResponse(status: .noContent),
            body: .none
        )

        let formatted = ResponseFormatter().format(response)

        #expect(formatted.contains("HTTP/1.1 204 No Content"))
        #expect(!formatted.contains("\n\n\n"))
        #expect(!formatted.contains("HTTP/1.1 204 No Content\n\n\n"))
    }
}
