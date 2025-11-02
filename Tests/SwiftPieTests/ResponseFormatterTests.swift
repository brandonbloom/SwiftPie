import HTTPTypes
import Testing
@testable import SwiftPie

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

        let formatted = ResponseFormatter(pretty: .all).format([response])
        let plain = strippingANSI(formatted)

        #expect(formatted.contains("\u{001B}["))
        #expect(plain.contains("HTTP/1.1 200 OK"))
        #expect(plain.contains("Content-Type: application/json"))
        #expect(plain.contains("X-Custom: value"))
        #expect(plain.contains("\"message\" : \"hello\""))
    }

    @Test("Omits body section when response body is empty")
    func omitsBodyWhenEmpty() {
        let response = ResponsePayload(
            response: HTTPResponse(status: .noContent),
            body: .none
        )

        let formatted = ResponseFormatter(pretty: .format).format([response])

        #expect(formatted.contains("HTTP/1.1 204 No Content"))
        #expect(!formatted.contains("\n\n\n"))
        #expect(!formatted.contains("HTTP/1.1 204 No Content\n\n\n"))
    }

    @Test("Formats redirect chains sequentially")
    func formatsRedirectChains() {
        let redirect = ResponsePayload(
            response: HTTPResponse(status: HTTPResponse.Status(code: 302)),
            body: .none
        )

        let final = ResponsePayload(
            response: HTTPResponse(status: .ok),
            body: .text("done")
        )

        let formatted = ResponseFormatter(pretty: .all).format([redirect, final])

        #expect(formatted.contains("HTTP/1.1 302 Found"))
        #expect(formatted.contains("HTTP/1.1 200 OK"))
        #expect(formatted.contains("done"))
    }

    @Test("Disables colors and formatting in none mode")
    func disablesFormattingInNoneMode() {
        let response = ResponsePayload(
            response: HTTPResponse(status: .ok),
            body: .text("{\"message\":\"hello\"}")
        )

        let formatted = ResponseFormatter(pretty: .none).format([response])

        #expect(!formatted.contains("\u{001B}["))
        #expect(formatted.contains("{\"message\":\"hello\"}"))
        #expect(!formatted.contains("\n    \"message\""))
    }

    @Test("Applies JSON indentation when format enabled")
    func indentsJsonWhenFormattingEnabled() {
        let response = ResponsePayload(
            response: HTTPResponse(status: .ok),
            body: .text("{\"message\":\"hello\",\"count\":1}")
        )

        let formatted = ResponseFormatter(pretty: .format).format([response])

        #expect(formatted.contains("\n  \"message\""))
        #expect(!formatted.contains("\u{001B}["))
    }

    @Test("Applies ANSI styling when colors enabled")
    func appliesColorsWhenEnabled() {
        let response = ResponsePayload(
            response: HTTPResponse(status: .ok),
            body: .text("{\"message\":\"hello\"}")
        )

        let formatted = ResponseFormatter(pretty: .colors).format([response])

        #expect(formatted.contains("\u{001B}["))
        #expect(formatted.contains("HTTP/1.1"))
    }
}

private func strippingANSI(_ text: String) -> String {
    text.replacingOccurrences(
        of: "\u{001B}\\[[0-9;]*m",
        with: "",
        options: .regularExpression
    )
}
