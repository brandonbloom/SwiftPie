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
            context: CLIContext(console: console, input: NonInteractiveInput())
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
            context: CLIContext(console: console, input: NonInteractiveInput())
        )

        #expect(exitCode == Int(EX_USAGE))
        #expect(console.output.isEmpty)
        #expect(console.error.contains("invalid URL"))
    }

    @Test("Builds request payload, sends it via the transport, and renders the response")
    func rendersTransportResponse() throws {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()
        let response = ResponsePayload(
            response: HTTPResponse(status: .ok),
            body: .text("OK")
        )
        transport.queue(result: .success(response))

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
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(exitCode == 0)

        let payload = try #require(transport.payloads.first)
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

        #expect(console.output.contains("HTTP/1.1 200 OK"))
        #expect(console.output.contains("Content-Length: 2") == false)
        #expect(console.output.contains("OK"))
        #expect(console.error.isEmpty)
    }

    @Test("Reports transport failures with exit code 1")
    func reportsTransportFailures() {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()
        transport.queue(result: .failure(.networkError("unreachable host")))

        let exitCode = SwiftHTTPie.run(
            arguments: ["SwiftHTTPie", "https://example.com"],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(exitCode == 1)
        #expect(console.output.isEmpty)
        #expect(console.error.contains("transport error: unreachable host"))
    }

    @Test("Reports unknown options before attempting to parse the request")
    func reportsUnknownOptions() {
        let console = ConsoleRecorder()
        let exitCode = SwiftHTTPie.run(
            arguments: ["SwiftHTTPie", "--unknown", "localhost"],
            context: CLIContext(console: console, input: NonInteractiveInput())
        )

        #expect(exitCode == Int(EX_USAGE))
        #expect(console.output.isEmpty)
        #expect(console.error.contains("unknown option '--unknown'"))
    }

    @Test("Returns non-zero exit codes for 4xx/5xx responses")
    func exitsWithErrorForClientAndServerErrors() {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()
        let notFound = ResponsePayload(
            response: HTTPResponse(status: .notFound),
            body: .text("missing")
        )
        transport.queue(result: .success(notFound))

        let exitCode = SwiftHTTPie.run(
            arguments: ["SwiftHTTPie", "https://example.com/missing"],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(exitCode == 1)
        #expect(console.output.contains("HTTP/1.1 404 Not Found"))
        #expect(console.output.contains("missing"))
        #expect(console.error.isEmpty)
    }

    @Test("Applies basic authorization header when credentials are supplied via -a")
    func appliesBasicAuthorizationHeader() throws {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()
        let response = ResponsePayload(
            response: HTTPResponse(status: .ok),
            body: .none
        )
        transport.queue(result: .success(response))

        let exitCode = SwiftHTTPie.run(
            arguments: [
                "SwiftHTTPie",
                "-a",
                "user:pass",
                "https://example.com"
            ],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(exitCode == 0)

        let payload = try #require(transport.payloads.first)
        let authorization = try #require(HTTPField.Name("Authorization"))
        #expect(payload.request.headerFields[values: authorization] == ["Basic dXNlcjpwYXNz"])
    }

    @Test("Prompts for missing password when stdin is interactive")
    func promptsForPasswordWhenMissing() throws {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()
        let response = ResponsePayload(
            response: HTTPResponse(status: .ok),
            body: .none
        )
        transport.queue(result: .success(response))

        let input = InteractiveInput(lines: ["secret\n"])

        let exitCode = SwiftHTTPie.run(
            arguments: [
                "SwiftHTTPie",
                "--auth",
                "user",
                "https://example.com"
            ],
            context: CLIContext(
                console: console,
                input: input,
                transport: transport
            )
        )

        #expect(exitCode == 0)
        #expect(console.error.contains("Enter password for user 'user':"))

        let payload = try #require(transport.payloads.first)
        let authorization = try #require(HTTPField.Name("Authorization"))
        #expect(payload.request.headerFields[values: authorization] == ["Basic dXNlcjpzZWNyZXQ="])
    }

    @Test("Fails when password prompt would read from ignored stdin")
    func failsWhenIgnoreStdinPreventsPrompt() {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()
        transport.queue(result: .failure(.internalFailure("should not be used")))

        let exitCode = SwiftHTTPie.run(
            arguments: [
                "SwiftHTTPie",
                "--ignore-stdin",
                "--auth",
                "user",
                "https://example.com"
            ],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(exitCode == Int(EX_USAGE))
        #expect(console.error.contains("password prompt is disabled when --ignore-stdin is set"))
        #expect(transport.payloads.isEmpty)
    }

    @Test("Applies bearer authorization when requested")
    func appliesBearerAuthorization() throws {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()
        let response = ResponsePayload(
            response: HTTPResponse(status: .ok),
            body: .none
        )
        transport.queue(result: .success(response))

        let exitCode = SwiftHTTPie.run(
            arguments: [
                "SwiftHTTPie",
                "--auth-type=bearer",
                "--auth",
                "token",
                "https://example.com"
            ],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(exitCode == 0)

        let payload = try #require(transport.payloads.first)
        let authorization = try #require(HTTPField.Name("Authorization"))
        #expect(payload.request.headerFields[values: authorization] == ["Bearer token"])
    }

    @Test("Propagates timeout and verification flags to the transport")
    func propagatesTransportOptions() throws {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()
        let response = ResponsePayload(
            response: HTTPResponse(status: .ok),
            body: .none
        )
        transport.queue(result: .success(response))

        let exitCode = SwiftHTTPie.run(
            arguments: [
                "SwiftHTTPie",
                "--timeout=2.5",
                "--verify=false",
                "--http1",
                "https://example.com"
            ],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(exitCode == 0)

        let options = try #require(transport.options.first)
        #expect(options.timeout == 2.5)
        #expect(options.verify == .disabled)
        #expect(options.httpVersionPreference == .http1Only)
    }

    @Test("Rejects invalid timeout values")
    func rejectsInvalidTimeoutValues() {
        let console = ConsoleRecorder()
        let exitCode = SwiftHTTPie.run(
            arguments: [
                "SwiftHTTPie",
                "--timeout=not-a-number",
                "https://example.com"
            ],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput()
            )
        )

        #expect(exitCode == Int(EX_USAGE))
        #expect(console.error.contains("invalid timeout value"))
    }

    @Test("Rejects unknown auth types")
    func rejectsUnknownAuthTypes() {
        let console = ConsoleRecorder()
        let exitCode = SwiftHTTPie.run(
            arguments: [
                "SwiftHTTPie",
                "--auth-type",
                "digest",
                "--auth",
                "user:pass",
                "https://example.com"
            ],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput()
            )
        )

        #expect(exitCode == Int(EX_USAGE))
        #expect(console.error.contains("unsupported auth type 'digest'"))
    }

    @Test("Rejects auth type usage without credentials")
    func rejectsAuthTypeWithoutCredentials() {
        let console = ConsoleRecorder()
        let exitCode = SwiftHTTPie.run(
            arguments: [
                "SwiftHTTPie",
                "--auth-type=bearer",
                "https://example.com"
            ],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput()
            )
        )

        #expect(exitCode == Int(EX_USAGE))
        #expect(console.error.contains("--auth-type requires --auth"))
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

private final class TransportRecorder: RequestTransport {
    private(set) var payloads: [RequestPayload] = []
    private(set) var options: [TransportOptions] = []
    private var results: [Result<ResponsePayload, TransportError>] = []

    func queue(result: Result<ResponsePayload, TransportError>) {
        results.append(result)
    }

    func send(_ payload: RequestPayload, options: TransportOptions) throws -> ResponsePayload {
        payloads.append(payload)
        self.options.append(options)

        guard !results.isEmpty else {
            throw TransportError.internalFailure("no queued transport result")
        }

        let result = results.removeFirst()
        switch result {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }
}

private struct NonInteractiveInput: InputSource {
    var isInteractive: Bool { false }

    func readSecureLine(prompt: String) -> String? {
        nil
    }
}

private final class InteractiveInput: InputSource {
    private var lines: [String]
    private(set) var prompts: [String] = []

    init(lines: [String]) {
        self.lines = lines
    }

    var isInteractive: Bool { true }

    func readSecureLine(prompt: String) -> String? {
        prompts.append(prompt)
        guard !lines.isEmpty else {
            return nil
        }

        return lines.removeFirst()
    }
}
