#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

import HTTPTypes
import Testing
@testable import SwiftHTTPieCore

@Suite("CLI runner")
struct CLIRunnerTests {
    @Test("Displays help when no arguments are supplied")
    func displaysHelpForEmptyArguments() {
        let console = ConsoleRecorder()
        let exitCode = SwiftHTTPie.run(
            arguments: ["SwiftHTTPie"],
            environment: CLIEnvironment(console: console)
        )

        #expect(exitCode == 0)
        #expect(console.output.contains("usage: SwiftHTTPie"))
        #expect(console.error.isEmpty)
    }

    @Test("Reports parser errors to stderr with usage exit code")
    func reportsParserErrors() {
        let console = ConsoleRecorder()
        let exitCode = SwiftHTTPie.run(
            arguments: ["SwiftHTTPie", "invalid::token"],
            environment: CLIEnvironment(console: console)
        )

        #expect(exitCode == Int(EX_USAGE))
        #expect(console.output.isEmpty)
        #expect(console.error.contains("invalid URL"))
    }

    @Test("Builds request payload and delivers it to the sink")
    func deliversParsedRequestToSink() throws {
        let console = ConsoleRecorder()
        var receivedPayloads: [RequestPayload] = []

        let exitCode = SwiftHTTPie.run(
            arguments: [
                "SwiftHTTPie",
                "POST",
                "https://example.com/path",
                "Authorization:Bearer token",
                "Clear-Header:",
                "name=value",
                "name=value2"
            ],
            environment: CLIEnvironment(
                console: console,
                requestSink: { payload in
                    receivedPayloads.append(payload)
                }
            )
        )

        #expect(exitCode == 0)

        let payload = try #require(receivedPayloads.first)
        #expect(payload.request.method.rawValue == "POST")
        #expect(payload.request.scheme == "https")
        #expect(payload.request.authority == "example.com")
        #expect(payload.request.path == "/path")

        let authorization = try #require(HTTPField.Name("Authorization"))
        #expect(payload.request.headerFields[values: authorization] == ["Bearer token"])

        let clearHeader = try #require(HTTPField.Name("Clear-Header"))
        #expect(payload.headerRemovals.contains(clearHeader))

        #expect(payload.data == [
            DataField(name: "name", value: .text("value")),
            DataField(name: "name", value: .text("value2"))
        ])

        #expect(console.output.contains("Request prepared"))
        #expect(console.error.isEmpty)
    }
}

private final class ConsoleRecorder: Console {
    private(set) var output = ""
    private(set) var error = ""

    func write(_ text: String, to stream: ConsoleStream) {
        switch stream {
        case .standardOutput:
            output.append(text)
        case .standardError:
            error.append(text)
        }
    }
}

extension ConsoleRecorder: @unchecked Sendable {}
