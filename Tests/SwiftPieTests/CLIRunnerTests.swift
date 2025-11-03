#if canImport(Darwin)
@preconcurrency import Darwin
#else
@preconcurrency import Glibc
#endif

import Foundation
import HTTPTypes
import Testing
import SwiftPieTestSupport
@testable import SwiftPie

@Suite("CLI runner")
struct CLIRunnerTests {
    @Test("Displays help when no arguments are supplied")
    func displaysHelpForEmptyArguments() {
        let console = ConsoleRecorder()
        let exitCode = SwiftPie.run(
            arguments: ["spie"],
            context: CLIContext(console: console, input: NonInteractiveInput())
        )

        #expect(exitCode == 0)
        #expect(console.output.contains("Show this help message and exit."))
        #expect(console.output.contains("Positional Arguments"))
        #expect(console.output.contains("--transport"))
        #expect(console.error.isEmpty)
    }

    @Test("Reports parser errors to stderr with usage exit code")
    func reportsParserErrors() {
        let console = ConsoleRecorder()
        let exitCode = SwiftPie.run(
            arguments: ["spie", "invalid::token"],
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

        let exitCode = SwiftPie.run(
            arguments: [
                "spie",
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

        let exitCode = SwiftPie.run(
            arguments: ["spie", "https://example.com"],
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

    @Test("Switches the default scheme to https when --ssl is provided")
    func switchesDefaultSchemeWithSSLFlag() throws {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()
        let response = ResponsePayload(
            response: HTTPResponse(status: .ok),
            body: .none
        )
        transport.queue(result: .success(response))

        let exitCode = SwiftPie.run(
            arguments: ["spie", "--ssl", "example.com/path"],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(exitCode == 0)

        let payload = try #require(transport.payloads.first)
        #expect(payload.request.scheme == "https")
        #expect(payload.request.authority == "example.com")
        #expect(payload.request.path == "/path")
    }

    @Test("Reports unknown options before attempting to parse the request")
    func reportsUnknownOptions() {
        let console = ConsoleRecorder()
        let exitCode = SwiftPie.run(
            arguments: ["spie", "--unknown", "localhost"],
            context: CLIContext(console: console, input: NonInteractiveInput())
        )

        #expect(exitCode == Int(EX_USAGE))
        #expect(console.output.isEmpty)
        #expect(console.error.contains("unknown option '--unknown'"))
    }

    @Test("Defaults to zero exit code for HTTP error responses")
    func defaultsToZeroExitCodeForHttpErrors() {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()
        let notFound = ResponsePayload(
            response: HTTPResponse(status: .notFound),
            body: .text("missing")
        )
        transport.queue(result: .success(notFound))

        let exitCode = SwiftPie.run(
            arguments: ["spie", "https://example.com/missing"],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(exitCode == 0)
        #expect(console.output.contains("HTTP/1.1 404 Not Found"))
        #expect(console.output.contains("missing"))
        #expect(console.error.isEmpty)
    }

    @Test("Honors --pretty options for response output")
    func honorsPrettyOptionValues() {
        let transport = TransportRecorder()
        let response = ResponsePayload(
            response: HTTPResponse(status: .ok),
            body: .text("{\"message\":\"hello\",\"count\":1}")
        )
        transport.queue(result: .success(response))

        let noneConsole = ConsoleRecorder()
        let noneExit = SwiftPie.run(
            arguments: ["spie", "--pretty=none", "https://example.com"],
            context: CLIContext(
                console: noneConsole,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(noneExit == 0)
        #expect(!noneConsole.output.contains("\u{001B}["))
        #expect(!noneConsole.output.contains("\n    \"message\""))

        transport.queue(result: .success(response))

        let formatConsole = ConsoleRecorder()
        let formatExit = SwiftPie.run(
            arguments: ["spie", "--pretty=format", "https://example.com"],
            context: CLIContext(
                console: formatConsole,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(formatExit == 0)
        #expect(!formatConsole.output.contains("\u{001B}["))
        #expect(formatConsole.output.contains("\n  \"message\""))

        transport.queue(result: .success(response))

        let colorsConsole = ConsoleRecorder()
        let colorsExit = SwiftPie.run(
            arguments: ["spie", "--pretty=colors", "https://example.com"],
            context: CLIContext(
                console: colorsConsole,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(colorsExit == 0)
        #expect(colorsConsole.output.contains("\u{001B}["))
        #expect(!colorsConsole.output.contains("\n  \"message\""))

        transport.queue(result: .success(response))

        let allConsole = ConsoleRecorder()
        let allExit = SwiftPie.run(
            arguments: ["spie", "--pretty=all", "https://example.com"],
            context: CLIContext(
                console: allConsole,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(allExit == 0)
        #expect(allConsole.output.contains("\u{001B}["))
        #expect(allConsole.output.contains("\n  \"message\""))
    }

    @Test("Defaults to all pretty when console is a terminal")
    func defaultsToAllPrettyWhenTerminal() {
        let transport = TransportRecorder()
        let response = ResponsePayload(
            response: HTTPResponse(status: .ok),
            body: .text("{\"message\":\"hello\"}")
        )
        transport.queue(result: .success(response))

        let console = ConsoleRecorder(isTerminal: true)
        let exitCode = SwiftPie.run(
            arguments: ["spie", "https://example.com"],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(exitCode == 0)
        #expect(console.output.contains("\u{001B}["))
        #expect(console.output.contains("\n  \"message\""))
    }

    @Test("Defaults to none pretty when console is not a terminal")
    func defaultsToNonePrettyWhenConsoleIsNotTerminal() {
        let transport = TransportRecorder()
        let response = ResponsePayload(
            response: HTTPResponse(status: .ok),
            body: .text("{\"message\":\"hello\"}")
        )
        transport.queue(result: .success(response))

        let console = ConsoleRecorder(isTerminal: false)
        let exitCode = SwiftPie.run(
            arguments: ["spie", "https://example.com"],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(exitCode == 0)
        #expect(!console.output.contains("\u{001B}["))
        #expect(!console.output.contains("\n  \"message\""))
    }

    @Test("Rejects unknown pretty values")
    func rejectsUnknownPrettyValues() {
        let console = ConsoleRecorder()
        let exitCode = SwiftPie.run(
            arguments: ["spie", "--pretty=invalid", "https://example.com"],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput()
            )
        )

        #expect(exitCode == Int(EX_USAGE))
        #expect(console.output.isEmpty)
        #expect(console.error.contains("invalid value for --pretty"))
    }

    @Test("Rejects unknown transport identifiers")
    func rejectsUnknownTransportIdentifiers() {
        let console = ConsoleRecorder()
        let exitCode = SwiftPie.run(
            arguments: ["spie", "--transport=invalid", "https://example.com"],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput()
            )
        )

        #expect(exitCode == Int(EX_USAGE))
        #expect(console.output.isEmpty)
        #expect(console.error.contains("invalid transport 'invalid'"))
    }

    @Test("Selects transport implementations via --transport")
    func selectsTransportByIdentifier() {
        let console = ConsoleRecorder()
        let recorder = TransportSelectionRecorder()
        let alphaID = TransportID("alpha")
        let betaID = TransportID("beta")

        let registry = TransportRegistry(
            defaultID: alphaID,
            descriptors: [
                TransportDescriptor(
                    id: alphaID,
                    label: "Alpha",
                    kind: .runtimeSelectable,
                    capabilities: [],
                    isSupported: { true },
                    makeTransport: {
                        AnyRequestTransport(StubTransport(identifier: "alpha", recorder: recorder))
                    }
                ),
                TransportDescriptor(
                    id: betaID,
                    label: "Beta",
                    kind: .runtimeSelectable,
                    capabilities: [],
                    isSupported: { true },
                    makeTransport: {
                        AnyRequestTransport(StubTransport(identifier: "beta", recorder: recorder))
                    }
                )
            ]
        )

        let exitCode = SwiftPie.run(
            arguments: ["spie", "--transport=beta", "https://example.com"],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transportRegistry: registry
            )
        )

        #expect(exitCode == 0)
        #expect(recorder.identifiers == ["beta"])
        #expect(console.output.contains("HTTP/1.1 200 OK"))
    }

    @Test("Maps --check-status to HTTP-aware exit codes")
    func checkStatusMapsToHttpExitCodes() throws {
        let transport = TransportRecorder()

        var redirectHeaders = HTTPFields()
        let location = try #require(HTTPField.Name("Location"))
        redirectHeaders.append(HTTPField(name: location, value: "https://example.com/next"))

        let redirect = ResponsePayload(
            response: HTTPResponse(status: HTTPResponse.Status(code: 302), headerFields: redirectHeaders),
            body: .none
        )

        transport.queue(result: .success(redirect))

        let redirectConsole = ConsoleRecorder()
        let redirectExit = SwiftPie.run(
            arguments: ["spie", "--check-status", "https://example.com/start"],
            context: CLIContext(
                console: redirectConsole,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(redirectExit == 3)
        #expect(redirectConsole.error.contains("HTTP 302 Found"))

        let notFound = ResponsePayload(
            response: HTTPResponse(status: .notFound),
            body: .none
        )
        transport.queue(result: .success(notFound))

        let notFoundConsole = ConsoleRecorder()
        let notFoundExit = SwiftPie.run(
            arguments: ["spie", "--check-status", "https://example.com/missing"],
            context: CLIContext(
                console: notFoundConsole,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(notFoundExit == 4)
        #expect(notFoundConsole.error.contains("HTTP 404 Not Found"))

        let serverError = ResponsePayload(
            response: HTTPResponse(status: .internalServerError),
            body: .none
        )
        transport.queue(result: .success(serverError))

        let serverErrorConsole = ConsoleRecorder()
        let serverErrorExit = SwiftPie.run(
            arguments: ["spie", "--check-status", "https://example.com/error"],
            context: CLIContext(
                console: serverErrorConsole,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(serverErrorExit == 5)
        #expect(serverErrorConsole.error.contains("HTTP 500 Internal Server Error"))
    }

    @Test("Follows redirects when --follow is provided")
    func followsRedirectsWithFollowFlag() throws {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()

        var redirectHeaders = HTTPFields()
        let location = try #require(HTTPField.Name("Location"))
        redirectHeaders.append(HTTPField(name: location, value: "https://example.com/second"))

        let redirect = ResponsePayload(
            response: HTTPResponse(status: HTTPResponse.Status(code: 302), headerFields: redirectHeaders),
            body: .none
        )

        let final = ResponsePayload(
            response: HTTPResponse(status: .ok),
            body: .text("done")
        )

        transport.queue(result: .success(redirect))
        transport.queue(result: .success(final))

        let exitCode = SwiftPie.run(
            arguments: ["spie", "--follow", "https://example.com/start"],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(exitCode == 0)
        #expect(transport.payloads.count == 2)

        let second = try #require(transport.payloads.last)
        #expect(second.request.path == "/second")

        #expect(console.output.contains("HTTP/1.1 302 Found"))
        #expect(console.output.contains("HTTP/1.1 200 OK"))
    }

    @Test("Respects --max-redirects guardrail")
    func respectsMaxRedirects() throws {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()

        var repeatHeaders = HTTPFields()
        let location = try #require(HTTPField.Name("Location"))
        repeatHeaders.append(HTTPField(name: location, value: "https://example.com/loop"))

        let redirect = ResponsePayload(
            response: HTTPResponse(status: HTTPResponse.Status(code: 302), headerFields: repeatHeaders),
            body: .none
        )

        transport.queue(result: .success(redirect))
        transport.queue(result: .success(redirect))

        let exitCode = SwiftPie.run(
            arguments: ["spie", "--follow", "--max-redirects=1", "https://example.com/start"],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(exitCode == 6)
        #expect(console.error.contains("too many redirects"))
        #expect(console.output.contains("HTTP/1.1 302 Found"))
    }

    @Test("Combines --follow with --check-status using final response")
    func followAndCheckStatusUseFinalResponse() throws {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()

        var redirectHeaders = HTTPFields()
        let location = try #require(HTTPField.Name("Location"))
        redirectHeaders.append(HTTPField(name: location, value: "https://example.com/final"))

        let redirect = ResponsePayload(
            response: HTTPResponse(status: HTTPResponse.Status(code: 302), headerFields: redirectHeaders),
            body: .none
        )

        let ok = ResponsePayload(
            response: HTTPResponse(status: .ok),
            body: .none
        )

        transport.queue(result: .success(redirect))
        transport.queue(result: .success(ok))

        let exitCode = SwiftPie.run(
            arguments: ["spie", "--follow", "--check-status", "https://example.com/start"],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(exitCode == 0)
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

        let exitCode = SwiftPie.run(
            arguments: [
                "spie",
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

        let exitCode = SwiftPie.run(
            arguments: [
                "spie",
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

        let exitCode = SwiftPie.run(
            arguments: [
                "spie",
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

        let exitCode = SwiftPie.run(
            arguments: [
                "spie",
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

        let exitCode = SwiftPie.run(
            arguments: [
                "spie",
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
        let exitCode = SwiftPie.run(
            arguments: [
                "spie",
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
        let exitCode = SwiftPie.run(
            arguments: [
                "spie",
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

    @Test("Convenience run executes peer responder closure")
    func convenienceRunUsesPeerResponder() throws {
        let recorder = PeerRequestRecorder()

        let exitCode = SwiftPie.run(
            arguments: ["spie", "https://example.local/get"],
            responder: { request in
                recorder.capture(request)
                return ResponsePayload(
                    response: HTTPResponse(status: .ok),
                    body: .text("peer response")
                )
            }
        )

        #expect(exitCode == 0)

        let captured = try #require(recorder.request)
        #expect(captured.request.method == .get)
        #expect(captured.request.scheme == "https")
        #expect(captured.request.authority == "example.local")
        #expect(captured.request.path == "/get")
    }

    @Test("Convenience run allows overriding parser options")
    func convenienceRunRespectsParserOptions() throws {
        let recorder = PeerRequestRecorder()
        let baseURL = try #require(URL(string: "https://peer.local"))

        let exitCode = SwiftPie.run(
            arguments: ["spie", "/status/201"],
            parserOptions: RequestParserOptions(baseURL: baseURL),
            responder: { request in
                recorder.capture(request)
                return ResponsePayload(
                    response: HTTPResponse(status: .created),
                    body: .none
                )
            }
        )

        #expect(exitCode == 0)

        let captured = try #require(recorder.request)
        #expect(captured.request.authority == "peer.local")
        #expect(captured.request.path == "/status/201")
    }

    @Test("Forces form encoding when --form flag is supplied")
    func formFlagForcesFormEncoding() throws {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()
        let response = ResponsePayload(
            response: HTTPResponse(status: .ok),
            body: .none
        )
        transport.queue(result: .success(response))

        let exitCode = SwiftPie.run(
            arguments: ["spie", "--form", "https://example.com/post", "foo=bar"],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(exitCode == 0)

        let payload = try #require(transport.payloads.first)
        #expect(payload.bodyMode == .form)
        #expect(payload.rawBody == nil)
    }

    @Test("Rejects JSON fields when --form is used")
    func rejectsJSONFieldsInFormMode() {
        let console = ConsoleRecorder()
        let exitCode = SwiftPie.run(
            arguments: ["spie", "--form", "https://example.com/post", "flag:=true"],
            context: CLIContext(console: console, input: NonInteractiveInput())
        )

        #expect(exitCode == Int(EX_USAGE))
        #expect(console.error.contains("field 'flag' uses JSON data"))
    }

    @Test("Sets Accept header for --json flag")
    func setsAcceptHeaderForJSONFlag() throws {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()
        let response = ResponsePayload(
            response: HTTPResponse(status: .ok),
            body: .none
        )
        transport.queue(result: .success(response))

        let exitCode = SwiftPie.run(
            arguments: ["spie", "--json", "https://example.com/get"],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(exitCode == 0)

        let payload = try #require(transport.payloads.first)
        let accept = try #require(HTTPField.Name("Accept"))
        #expect(payload.request.headerFields[accept] == "application/json, */*;q=0.5")
    }

    @Test("Keeps explicit Accept header when --json is provided")
    func preservesExplicitAcceptHeaderWithJSONFlag() throws {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()
        let response = ResponsePayload(
            response: HTTPResponse(status: .ok),
            body: .none
        )
        transport.queue(result: .success(response))

        let exitCode = SwiftPie.run(
            arguments: ["spie", "--json", "https://example.com/get", "Accept:text/plain"],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(exitCode == 0)

        let payload = try #require(transport.payloads.first)
        let accept = try #require(HTTPField.Name("Accept"))
        #expect(payload.request.headerFields[accept] == "text/plain")
    }

    @Test("Captures raw body when --raw is provided")
    func rawFlagUsesRawBody() throws {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()
        let response = ResponsePayload(
            response: HTTPResponse(status: .ok),
            body: .none
        )
        transport.queue(result: .success(response))

        let exitCode = SwiftPie.run(
            arguments: ["spie", "--raw", "payload body", "POST", "https://example.com/post"],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(exitCode == 0)

        let payload = try #require(transport.payloads.first)
        #expect(payload.bodyMode == .raw)
        #expect(payload.rawBody == .inline("payload body"))
        #expect(payload.data.isEmpty)
    }

    @Test("Loads raw body from files")
    func rawFlagReadsFiles() throws {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()
        let response = ResponsePayload(
            response: HTTPResponse(status: .ok),
            body: .none
        )
        transport.queue(result: .success(response))

        let directory = FileManager.default.temporaryDirectory
        let fileURL = directory.appendingPathComponent(UUID().uuidString)
        try "file-body".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let exitCode = SwiftPie.run(
            arguments: ["spie", "--raw=@\(fileURL.path)", "POST", "https://example.com/post"],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(exitCode == 0)

        let payload = try #require(transport.payloads.first)
        let expected = try #require("file-body".data(using: .utf8))
        #expect(payload.bodyMode == .raw)
        #expect(payload.rawBody == .data(expected))
    }

    @Test("Rejects mixing request items with raw bodies")
    func rejectsRawWithRequestItems() {
        let console = ConsoleRecorder()
        let exitCode = SwiftPie.run(
            arguments: [
                "spie",
                "--raw",
                "raw body",
                "https://example.com/post",
                "foo=bar"
            ],
            context: CLIContext(console: console, input: NonInteractiveInput())
        )

        #expect(exitCode == Int(EX_USAGE))
        #expect(console.error.contains("cannot mix --raw with request items"))
    }

    @Test("Rejects stdin usage when --ignore-stdin is set")
    func rejectsStdinWhenIgnored() {
        let console = ConsoleRecorder()
        let exitCode = SwiftPie.run(
            arguments: [
                "spie",
                "--ignore-stdin",
                "https://example.com/post",
                "foo=@-"
            ],
            context: CLIContext(console: console, input: NonInteractiveInput())
        )

        #expect(exitCode == Int(EX_USAGE))
        #expect(console.error.contains("stdin is disabled by --ignore-stdin"))
    }

    @Test("Expands stdin data into request fields")
    func expandsStdinData() throws {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()
        let response = ResponsePayload(
            response: HTTPResponse(status: .ok),
            body: .none
        )
        transport.queue(result: .success(response))

        let input = BufferedInput(data: Data("stdin-body".utf8))

        let exitCode = SwiftPie.run(
            arguments: ["spie", "https://example.com/post", "body=@-"],
            context: CLIContext(
                console: console,
                input: input,
                transport: transport
            )
        )

        #expect(exitCode == 0)

        let payload = try #require(transport.payloads.first)
        let field = try #require(payload.data.first)
        #expect(field.name == "body")
        #expect(field.value == .text("stdin-body"))
    }

    @Test("Reads raw body from stdin")
    func rawBodyFromStdin() throws {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()
        let response = ResponsePayload(
            response: HTTPResponse(status: .ok),
            body: .none
        )
        transport.queue(result: .success(response))

        let input = BufferedInput(data: Data("raw-stdin".utf8))

        let exitCode = SwiftPie.run(
            arguments: ["spie", "--raw=@-", "POST", "https://example.com/post"],
            context: CLIContext(
                console: console,
                input: input,
                transport: transport
            )
        )

        #expect(exitCode == 0)

        let payload = try #require(transport.payloads.first)
        #expect(payload.bodyMode == .raw)
        #expect(payload.rawBody == .data(Data("raw-stdin".utf8)))
    }

    @Test("Rejects auth type usage without credentials")
    func rejectsAuthTypeWithoutCredentials() {
        let console = ConsoleRecorder()
        let exitCode = SwiftPie.run(
            arguments: [
                "spie",
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

    @Test("Quiet mode suppresses stdout but shows errors")
    func quietModeSuppressesStdoutOnly() {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()
        transport.queue(result: .failure(.networkError("connection failed")))

        let exitCode = SwiftPie.run(
            arguments: ["spie", "-q", "https://example.com"],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(exitCode == 1)
        #expect(console.output.isEmpty)
        #expect(console.error.contains("connection failed"))
    }

    @Test("Quiet mode with --quiet flag suppresses stdout but shows errors")
    func quietModeWithLongFlagSuppressesStdoutOnly() {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()
        transport.queue(result: .failure(.networkError("host unreachable")))

        let exitCode = SwiftPie.run(
            arguments: ["spie", "--quiet", "https://example.com"],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(exitCode == 1)
        #expect(console.output.isEmpty)
        #expect(console.error.contains("host unreachable"))
    }

    @Test("Very quiet mode suppresses all output including errors")
    func veryQuietModeSuppressesEverything() {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()
        transport.queue(result: .failure(.networkError("connection failed")))

        let exitCode = SwiftPie.run(
            arguments: ["spie", "-qq", "https://example.com"],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(exitCode == 1)
        #expect(console.output.isEmpty)
        #expect(console.error.isEmpty)
    }

    @Test("Quiet mode with successful response suppresses body and headers")
    func quietModeWithSuccessfulResponse() {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()
        let response = ResponsePayload(
            response: HTTPResponse(status: .ok),
            body: .text("Success response body")
        )
        transport.queue(result: .success(response))

        let exitCode = SwiftPie.run(
            arguments: ["spie", "-q", "https://example.com"],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(exitCode == 0)
        #expect(console.output.isEmpty)
        #expect(console.error.isEmpty)
    }

    @Test("Very quiet mode with successful response suppresses all output")
    func veryQuietModeWithSuccessfulResponse() {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()
        let response = ResponsePayload(
            response: HTTPResponse(status: .ok),
            body: .text("Success response body")
        )
        transport.queue(result: .success(response))

        let exitCode = SwiftPie.run(
            arguments: ["spie", "-qq", "https://example.com"],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(exitCode == 0)
        #expect(console.output.isEmpty)
        #expect(console.error.isEmpty)
    }

    @Test("Quiet mode shows HTTP errors to stderr when --check-status is used")
    func quietModeShowsHTTPErrorsWithCheckStatus() {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()
        let notFound = ResponsePayload(
            response: HTTPResponse(status: .notFound),
            body: .text("Not found")
        )
        transport.queue(result: .success(notFound))

        let exitCode = SwiftPie.run(
            arguments: ["spie", "-q", "--check-status", "https://example.com/missing"],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(exitCode == 4)
        #expect(console.output.isEmpty)
        #expect(console.error.contains("HTTP 404"))
    }

    @Test("Very quiet mode suppresses HTTP errors even with --check-status")
    func veryQuietModeSuppressesHTTPErrorsWithCheckStatus() {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()
        let notFound = ResponsePayload(
            response: HTTPResponse(status: .notFound),
            body: .text("Not found")
        )
        transport.queue(result: .success(notFound))

        let exitCode = SwiftPie.run(
            arguments: ["spie", "-qq", "--check-status", "https://example.com/missing"],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(exitCode == 4)
        #expect(console.output.isEmpty)
        #expect(console.error.isEmpty)
    }

    @Test("Quiet mode exit codes work correctly for successful requests")
    func quietModeExitCodesForSuccess() {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()
        let response = ResponsePayload(
            response: HTTPResponse(status: .ok),
            body: .text("OK")
        )
        transport.queue(result: .success(response))

        let exitCode = SwiftPie.run(
            arguments: ["spie", "-q", "https://example.com"],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(exitCode == 0)
    }

    @Test("Quiet mode exit codes work correctly for transport errors")
    func quietModeExitCodesForTransportErrors() {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()
        transport.queue(result: .failure(.networkError("timeout")))

        let exitCode = SwiftPie.run(
            arguments: ["spie", "-q", "https://example.com"],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(exitCode == 1)
    }

    @Test("Very quiet mode exit codes work correctly")
    func veryQuietModeExitCodesWork() {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()
        transport.queue(result: .failure(.networkError("error")))

        let exitCode = SwiftPie.run(
            arguments: ["spie", "-qq", "https://example.com"],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(exitCode == 1)
    }

    @Test("Normal mode displays response body and headers")
    func normalModeShowsOutput() {
        let console = ConsoleRecorder()
        let transport = TransportRecorder()
        let response = ResponsePayload(
            response: HTTPResponse(status: .ok),
            body: .text("Response body")
        )
        transport.queue(result: .success(response))

        let exitCode = SwiftPie.run(
            arguments: ["spie", "https://example.com"],
            context: CLIContext(
                console: console,
                input: NonInteractiveInput(),
                transport: transport
            )
        )

        #expect(exitCode == 0)
        #expect(console.output.contains("HTTP/1.1 200 OK"))
        #expect(console.output.contains("Response body"))
        #expect(console.error.isEmpty)
    }

    @Test("Quiet mode validation errors bypass quiet suppression")
    func quietModeValidationErrorsShown() {
        let console = ConsoleRecorder()
        let exitCode = SwiftPie.run(
            arguments: ["spie", "-q", "--unknown-flag", "https://example.com"],
            context: CLIContext(console: console, input: NonInteractiveInput())
        )

        #expect(exitCode == Int(EX_USAGE))
        #expect(console.error.contains("unknown option"))
    }
}

@Suite("SwiftNIO transport")
struct NIOTransportTests {
    @Test("Standard registry exposes the NIO transport option")
    func registryIncludesNIOTransport() {
        let registry = TransportRegistry.standard
        let identifiers = registry.selectableIdentifiers()
        #expect(identifiers.contains(.nio))
    }

    @Test("Direct transport requests succeed against the in-process server")
    func directRequestsSucceed() throws {
        try withTestServer { server in
            let registry = TransportRegistry.standard
            let transport = try registry.makeTransport(for: .nio)

            guard
                let scheme = server.baseURL.scheme,
                let host = server.baseURL.host
            else {
                Issue.record("Test server base URL is missing scheme or host.")
                return
            }

            let authority: String
            if let port = server.baseURL.port {
                authority = "\(host):\(port)"
            } else {
                authority = host
            }

            let request = HTTPRequest(
                method: .get,
                scheme: scheme,
                authority: authority,
                path: "/get"
            )

            let payload = RequestPayload(
                request: request,
                data: [],
                files: [],
                headerRemovals: []
            )

            let response = try transport.send(payload, options: TransportOptions())
            #expect(response.response.status == .ok)
            switch response.body {
            case .text(let text):
                #expect(text.contains("\"url\""))
            default:
                Issue.record("Expected text body for /get response.")
            }
        }
    }

    @Test("CLI uses the NIO transport when selected via --transport")
    func cliRunsRequestWithNIOTransport() throws {
        try withTestServer { server in
            let console = ConsoleRecorder()
            let exitCode = SwiftPie.run(
                arguments: ["spie", "--transport=nio", server.baseURL.appendingPathComponent("get").absoluteString],
                context: CLIContext(console: console, input: NonInteractiveInput())
            )

            #expect(exitCode == 0)
            #expect(console.output.contains("HTTP/1.1 200 OK"))
            #expect(console.output.contains("\"url\""))
            #expect(console.error.isEmpty)
        }
    }
}


private final class PeerRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: PeerRequest?

    func capture(_ request: PeerRequest) {
        lock.lock()
        storage = request
        lock.unlock()
    }

    var request: PeerRequest? {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class ConsoleRecorder: Console {
    private(set) var output = ""
    private(set) var error = ""
    let isOutputTerminal: Bool

    init(isTerminal: Bool = true) {
        self.isOutputTerminal = isTerminal
    }

    func write(_ text: String, to stream: ConsoleStream) {
        switch stream {
        case .standardOutput:
            output.append(text)
        case .standardError:
            error.append(text)
        }
    }
}

private final class TransportSelectionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var identifiers: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ identifier: String) {
        lock.lock()
        storage.append(identifier)
        lock.unlock()
    }
}

private final class StubTransport: RequestTransport {
    private let identifier: String
    private let recorder: TransportSelectionRecorder

    init(identifier: String, recorder: TransportSelectionRecorder) {
        self.identifier = identifier
        self.recorder = recorder
    }

    func send(_ payload: RequestPayload, options: TransportOptions) throws -> ResponsePayload {
        recorder.record(identifier)
        return ResponsePayload(
            response: HTTPResponse(status: .ok),
            body: .none
        )
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

    func readAllData() throws -> Data {
        Data()
    }
}

private struct BufferedInput: InputSource {
    var isInteractive: Bool { false }
    var data: Data

    func readSecureLine(prompt: String) -> String? {
        nil
    }

    func readAllData() throws -> Data {
        data
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

    func readAllData() throws -> Data {
        let combined = lines.joined()
        return Data(combined.utf8)
    }
}
