import Foundation
import Testing
@testable import SwiftPie

@Suite("Request parsing")
struct RequestParserTests {
    @Test("Parses explicit method, URL, and mixed request items")
    func parsesMixedRequestItems() throws {
        let arguments = [
            "POST",
            "https://example.com/resource",
            "Header:value",
            "Unset-Header:",
            "Empty-Header;",
            "string=value",
            "bool:=true",
            #"list:=["a", 1, {}, false]"#,
            "query==value"
        ]

        let parsed = try RequestParser.parse(arguments: arguments)

        #expect(parsed.method == .post)
        #expect(parsed.url.absoluteString == "https://example.com/resource?query=value")

        #expect(parsed.items.headers == [
            HeaderField(name: "Header", value: .some("value")),
            HeaderField(name: "Unset-Header", value: .none),
            HeaderField(name: "Empty-Header", value: .some(""))
        ])

        #expect(parsed.items.data == [
            DataField(name: "string", value: .text("value")),
            DataField(name: "bool", value: .json(.bool(true))),
            DataField(
                name: "list",
                value: .json(.array([
                    .string("a"),
                    .number(1),
                    .object([:]),
                    .bool(false)
                ]))
            )
        ])

        #expect(parsed.items.query == [
            QueryField(name: "query", values: ["value"])
        ])
    }

    @Test("Parses escaped separators")
    func parsesEscapedSeparators() throws {
        let arguments = [
            "GET",
            "https://example.com",
            #"foo\:bar:baz"#,
            #"jack\@jill:hill"#,
            #"baz\=bar=foo"#
        ]

        let parsed = try RequestParser.parse(arguments: arguments)

        #expect(parsed.items.headers == [
            HeaderField(name: "foo:bar", value: .some("baz")),
            HeaderField(name: "jack@jill", value: .some("hill"))
        ])

        #expect(parsed.items.data == [
            DataField(name: "baz=bar", value: .text("foo"))
        ])
    }

    @Test("Infers method when omitted and data is provided")
    func infersMethodFromData() throws {
        let arguments = [
            "https://api.example.com",
            "payload=value"
        ]

        let parsed = try RequestParser.parse(arguments: arguments)

        #expect(parsed.method == .post)
        #expect(parsed.url.absoluteString == "https://api.example.com")
        #expect(parsed.items.data == [
            DataField(name: "payload", value: .text("value"))
        ])
    }

    @Test("Expands localhost shorthand")
    func expandsLocalhostShorthand() throws {
        let parsed = try RequestParser.parse(arguments: [":3000/path"])
        #expect(parsed.url.absoluteString == "http://localhost:3000/path")

        let trailingSlash = try RequestParser.parse(arguments: [":/"])
        #expect(trailingSlash.url.absoluteString == "http://localhost/")

        let bareLocalhost = try RequestParser.parse(arguments: [":"])
        #expect(bareLocalhost.url.absoluteString == "http://localhost")
    }

    @Test("Merges duplicate query items from URL and arguments")
    func mergesDuplicateQueryItems() throws {
        let parsed = try RequestParser.parse(arguments: [
            "GET",
            "https://example.com/get?a=1",
            "a==1",
            "b==2"
        ])

        #expect(parsed.url.scheme == "https")
        #expect(parsed.url.host == "example.com")
        #expect(parsed.url.path == "/get")

        #expect(parsed.items.query == [
            QueryField(name: "a", values: ["1", "1"]),
            QueryField(name: "b", values: ["2"])
        ])
    }

    @Test("Parses duplicate headers and form fields")
    func parsesDuplicateHeadersAndData() throws {
        let parsed = try RequestParser.parse(arguments: [
            "https://example.com",
            "Header:one",
            "Header:two",
            "name=value",
            "name=value2"
        ])

        #expect(parsed.items.headers == [
            HeaderField(name: "Header", value: .some("one")),
            HeaderField(name: "Header", value: .some("two"))
        ])

        #expect(parsed.items.data == [
            DataField(name: "name", value: .text("value")),
            DataField(name: "name", value: .text("value2"))
        ])
    }

    @Test("Parses file embeds with escaped characters")
    func parsesFileEmbeds() throws {
        let parsed = try RequestParser.parse(arguments: [
            "POST",
            "https://example.com/upload",
            "file@/tmp/data.txt",
            #"escaped\ name@path\ with\ spaces"#
        ])

        #expect(parsed.items.files == [
            FileField(name: "file", path: URL(fileURLWithPath: "/tmp/data.txt")),
            FileField(name: "escaped name", path: URL(fileURLWithPath: "path with spaces"))
        ])
    }
}
