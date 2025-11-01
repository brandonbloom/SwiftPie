#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

import Foundation
import HTTPTypes
import Rainbow

public enum SwiftPie {
    /// Primary entry point invoked by the CLI executable.
    /// - Parameter arguments: The raw command-line arguments, usually `CommandLine.arguments`.
    /// - Returns: Never returns because it terminates the process with the exit code.
    public static func main(arguments: [String]) -> Never {
        let exitCode = run(arguments: arguments)
        exit(Int32(exitCode))
    }

    /// Primary entry point allowing callers to supply a custom context.
    /// - Parameters:
    ///   - arguments: The raw command-line arguments, usually `CommandLine.arguments`.
    ///   - context: Custom CLI dependencies such as transports or parser defaults.
    /// - Returns: Never returns because it terminates the process with the exit code.
    public static func main<Transport: RequestTransport>(
        arguments: [String],
        context: CLIContext<Transport>
    ) -> Never {
        let exitCode = run(arguments: arguments, context: context)
        exit(Int32(exitCode))
    }

    /// Utility that executes the CLI flow using the default context.
    public static func run(arguments: [String]) -> Int {
        run(arguments: arguments, context: CLIContext())
    }

    /// Utility that executes the CLI flow with a custom context.
    public static func run<Transport: RequestTransport>(
        arguments: [String],
        context: CLIContext<Transport>
    ) -> Int {
        let runner = CLIRunner(arguments: arguments, context: context)
        return runner.run()
    }

    /// Convenience entry point that wires the CLI to an in-process peer responder.
    /// - Parameters:
    ///   - arguments: Raw command-line arguments (defaults to `CommandLine.arguments`).
    ///   - parserOptions: Parser defaults applied before evaluating CLI input.
    ///   - responder: Closure handling requests without performing network I/O.
    /// - Returns: Never returns because it terminates the process with the exit code.
    public static func main(
        arguments: [String] = CommandLine.arguments,
        parserOptions: RequestParserOptions = .default,
        responder: @escaping PeerResponder
    ) -> Never {
        let exitCode = run(
            arguments: arguments,
            parserOptions: parserOptions,
            responder: responder
        )
        exit(Int32(exitCode))
    }

    /// Convenience runner that routes requests to a peer responder instead of the network.
    /// - Parameters:
    ///   - arguments: Raw command-line arguments (defaults to `CommandLine.arguments`).
    ///   - parserOptions: Parser defaults applied before evaluating CLI input.
    ///   - responder: Closure handling requests without performing network I/O.
    /// - Returns: The CLI exit code without terminating the process.
    public static func run(
        arguments: [String] = CommandLine.arguments,
        parserOptions: RequestParserOptions = .default,
        responder: @escaping PeerResponder
    ) -> Int {
        let context = CLIContext(
            transport: PeerTransport(responder: responder),
            parserOptions: parserOptions
        )
        return run(arguments: arguments, context: context)
    }
}

private struct ParsedCLIOptions {
    var showHelp: Bool
    var arguments: [String]
    var ignoreStdin: Bool
    var authValue: String?
    var authProvided: Bool
    var authType: AuthType
    var authTypeWasExplicit: Bool
   var verify: TransportOptions.TLSVerification
   var timeout: TimeInterval?
   var httpVersionPreference: TransportOptions.HTTPVersionPreference
   var defaultScheme: RequestParserOptions.DefaultScheme
   var bodyMode: RequestPayload.BodyMode
   var rawBody: RawBodyInput?
    var forceJSONAccept: Bool
}

private enum AuthType {
    case basic
    case bearer
}

private enum PromptUnavailableReason {
    case ignoreStdin
    case nonInteractive
}

private enum RawBodyInput: Equatable {
    case inline(String)
    case file(URL)
    case stdin
}

private struct OptionParser {
    var arguments: [String]

    func parse() throws -> ParsedCLIOptions {
        var remaining: [String] = []
        var showHelp = false
        var parsingOptions = true
        var ignoreStdin = false
        var authValue: String?
        var authProvided = false
        var authType: AuthType = .basic
        var authTypeExplicit = false
        var verify: TransportOptions.TLSVerification = .enforced
        var timeout: TimeInterval?
        var httpVersionPreference: TransportOptions.HTTPVersionPreference = .automatic
        var defaultScheme: RequestParserOptions.DefaultScheme = .http
        var bodyMode: RequestPayload.BodyMode = .json
        var rawBody: RawBodyInput?
        var bodyOptionName: String?
        var forceJSONAccept = false

        func setBodyMode(_ mode: RequestPayload.BodyMode, optionName: String) throws {
            if let existing = bodyOptionName, existing != optionName {
                throw CLIOptionError.conflictingBodyOptions(existing, optionName)
            }

            bodyMode = mode
            bodyOptionName = optionName

            if mode != .raw {
                rawBody = nil
            }
        }

        func parseRawBody(_ value: String) throws -> RawBodyInput {
            guard !value.isEmpty else {
                throw CLIOptionError.invalidRawValue(value)
            }

            if value.hasPrefix("@") {
                let pathPortion = String(value.dropFirst())
                if pathPortion == "-" {
                    return .stdin
                }
                guard !pathPortion.isEmpty else {
                    throw CLIOptionError.invalidRawValue(value)
                }
                return .file(URL(fileURLWithPath: pathPortion))
            }

            return .inline(value)
        }

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]

            if parsingOptions {
                if argument == "--" {
                    parsingOptions = false
                    index += 1
                    continue
                }

                if argument.hasPrefix("-"), argument != "-" {
                    switch argument {
                    case "-h", "--help":
                        showHelp = true
                        index += 1
                        continue
                    case "-I", "--ignore-stdin":
                        ignoreStdin = true
                        index += 1
                        continue
                    case "-j", "--json":
                        try setBodyMode(.json, optionName: "--json")
                        forceJSONAccept = true
                        index += 1
                        continue
                    case "-f", "--form":
                        try setBodyMode(.form, optionName: "--form")
                        index += 1
                        continue
                    case "--http1":
                        httpVersionPreference = .http1Only
                        index += 1
                        continue
                    case "--ssl":
                        defaultScheme = .https
                        index += 1
                        continue
                    default:
                        break
                    }

                    if argument.hasPrefix("--") {
                        let (name, inlineValue) = splitLongOption(argument)
                        switch name {
                        case "--auth":
                            let (value, nextIndex) = try consumeValue(
                                inline: inlineValue,
                                currentIndex: index,
                                option: "--auth"
                            )
                            authValue = value
                            authProvided = true
                            index = nextIndex
                            continue
                        case "--auth-type":
                            let (value, nextIndex) = try consumeValue(
                                inline: inlineValue,
                                currentIndex: index,
                                option: "--auth-type"
                            )
                            authType = try parseAuthType(value)
                            authTypeExplicit = true
                            index = nextIndex
                            continue
                        case "--timeout":
                            let (value, nextIndex) = try consumeValue(
                                inline: inlineValue,
                                currentIndex: index,
                                option: "--timeout"
                            )
                            guard let parsed = Double(value), parsed > 0 else {
                                throw CLIOptionError.invalidTimeout(value)
                            }
                            timeout = parsed
                            index = nextIndex
                            continue
                        case "--verify":
                            if let inlineValue {
                                verify = try parseVerify(inlineValue)
                                index += 1
                                continue
                            } else {
                                let (candidate, nextIndex) = consumeOptionalValue(currentIndex: index)
                                if let candidate {
                                    verify = try parseVerify(candidate)
                                    index = nextIndex
                                } else {
                                    verify = .enforced
                                    index += 1
                                }
                                continue
                            }
                        case "--raw":
                            let (value, nextIndex) = try consumeValue(
                                inline: inlineValue,
                                currentIndex: index,
                                option: "--raw"
                            )
                            try setBodyMode(.raw, optionName: "--raw")
                            rawBody = try parseRawBody(value)
                            index = nextIndex
                            continue
                        default:
                            throw CLIOptionError.unknownOption(argument)
                        }
                    } else if argument.hasPrefix("-a") {
                        let remainder = String(argument.dropFirst(2))
                        if remainder.isEmpty {
                            let nextIndex = index + 1
                            guard nextIndex < arguments.count else {
                                throw CLIOptionError.missingValue("-a")
                            }
                            authValue = arguments[nextIndex]
                            authProvided = true
                            index = nextIndex + 1
                        } else {
                            authValue = remainder
                            authProvided = true
                            index += 1
                        }
                        continue
                    } else {
                        throw CLIOptionError.unknownOption(argument)
                    }
                }
            }

            parsingOptions = false
            remaining.append(argument)
            index += 1
        }

        return ParsedCLIOptions(
            showHelp: showHelp,
            arguments: remaining,
            ignoreStdin: ignoreStdin,
            authValue: authValue,
            authProvided: authProvided,
            authType: authType,
            authTypeWasExplicit: authTypeExplicit,
            verify: verify,
            timeout: timeout,
            httpVersionPreference: httpVersionPreference,
            defaultScheme: defaultScheme,
            bodyMode: bodyMode,
            rawBody: rawBody,
            forceJSONAccept: forceJSONAccept
        )
    }

    private func splitLongOption(_ argument: String) -> (String, String?) {
        guard let equalIndex = argument.firstIndex(of: "=") else {
            return (argument, nil)
        }

        let name = String(argument[..<equalIndex])
        let valueStart = argument.index(after: equalIndex)
        let value = String(argument[valueStart...])
        return (name, value)
    }

    private func consumeValue(
        inline: String?,
        currentIndex: Int,
        option: String
    ) throws -> (String, Int) {
        if let inline {
            return (inline, currentIndex + 1)
        }

        let nextIndex = currentIndex + 1
        guard nextIndex < arguments.count else {
            throw CLIOptionError.missingValue(option)
        }

        return (arguments[nextIndex], nextIndex + 1)
    }

    private func consumeOptionalValue(
        currentIndex: Int
    ) -> (String?, Int) {
        let nextIndex = currentIndex + 1
        guard nextIndex < arguments.count else {
            return (nil, currentIndex + 1)
        }

        let candidate = arguments[nextIndex]
        if candidate == "--" || (candidate.hasPrefix("-") && candidate != "-") {
            return (nil, currentIndex + 1)
        }

        return (candidate, nextIndex + 1)
    }

    private func parseAuthType(_ value: String) throws -> AuthType {
        switch value.lowercased() {
        case "basic":
            return .basic
        case "bearer":
            return .bearer
        default:
            throw CLIOptionError.invalidAuthType(value)
        }
    }

    private func parseVerify(_ value: String) throws -> TransportOptions.TLSVerification {
        let normalized = value.lowercased()
        switch normalized {
        case "true", "yes", "1":
            return .enforced
        case "false", "no", "0":
            return .disabled
        default:
            throw CLIOptionError.invalidVerifyValue(value)
        }
    }
}

private enum CLIOptionError: Error {
    case unknownOption(String)
    case missingValue(String)
    case invalidTimeout(String)
    case invalidVerifyValue(String)
    case invalidAuthType(String)
    case authTypeRequiresAuth
    case passwordPromptUnavailable(PromptUnavailableReason)
    case passwordPromptCancelled
    case conflictingBodyOptions(String, String)
    case invalidRawValue(String)
    case stdinDisabled
}

private extension CLIOptionError {
    var cliDescription: String {
        switch self {
        case .unknownOption(let option):
            return "unknown option '\(option)'"
        case .missingValue(let option):
            return "missing value for option '\(option)'"
        case .invalidTimeout(let value):
            return "invalid timeout value '\(value)'"
        case .invalidVerifyValue(let value):
            return "invalid verify value '\(value)'"
        case .invalidAuthType(let type):
            return "unsupported auth type '\(type)'"
        case .authTypeRequiresAuth:
            return "--auth-type requires --auth"
        case .passwordPromptUnavailable(let reason):
            switch reason {
            case .ignoreStdin:
                return "password prompt is disabled when --ignore-stdin is set"
            case .nonInteractive:
                return "password prompt requires an interactive stdin"
            }
        case .passwordPromptCancelled:
            return "password prompt cancelled"
        case .conflictingBodyOptions(let existing, let option):
            return "conflicting body options '\(existing)' and '\(option)'"
        case .invalidRawValue(let value):
            return "invalid raw body value '\(value)'"
        case .stdinDisabled:
            return "stdin is disabled by --ignore-stdin"
        }
    }
}

public struct CLIContext<Transport: RequestTransport> {
    public var console: any Console
    public var input: any InputSource
    public var transport: Transport
    public var parserOptions: RequestParserOptions

    public init(
        console: any Console = StandardConsole(),
        input: any InputSource = StandardInput(),
        transport: Transport,
        parserOptions: RequestParserOptions = .default
    ) {
        self.console = console
        self.input = input
        self.transport = transport
        self.parserOptions = parserOptions
    }
}

public extension CLIContext where Transport == URLSessionTransport {
    init(
        console: any Console = StandardConsole(),
        input: any InputSource = StandardInput(),
        transport: Transport = URLSessionTransport(),
        parserOptions: RequestParserOptions = .default
    ) {
        self.console = console
        self.input = input
        self.transport = transport
        self.parserOptions = parserOptions
    }
}

private let usageExitCode: Int = {
    #if canImport(Darwin)
    Int(EX_USAGE)
    #else
    Int(EX_USAGE)
    #endif
}()

private enum ExitCode {
    case success
    case usage
    case failure

    var rawValue: Int {
        switch self {
        case .success:
            return 0
        case .usage:
            return usageExitCode
        case .failure:
            return 1
        }
    }
}

private struct CLIRunner<Transport: RequestTransport> {
    private let arguments: [String]
    private let context: CLIContext<Transport>

    init(arguments: [String], context: CLIContext<Transport>) {
        self.arguments = arguments
        self.context = context
    }

    func run() -> Int {
        let userArguments = Array(arguments.dropFirst())

        do {
            let options = try OptionParser(arguments: userArguments).parse()

            if options.showHelp || options.arguments.isEmpty {
                context.console.out(helpText)
                return ExitCode.success.rawValue
            }

            if options.authTypeWasExplicit && !options.authProvided {
                throw CLIOptionError.authTypeRequiresAuth
            }

            var parserOptions = context.parserOptions
            parserOptions.defaultScheme = options.defaultScheme
            var parsed = try RequestParser.parse(
                arguments: options.arguments,
                options: parserOptions
            )

            let needsStdin = requiresStdin(parsed: parsed, rawBody: options.rawBody)

            if needsStdin && options.ignoreStdin {
                throw CLIOptionError.stdinDisabled
            }

            var stdinData: Data?
            if needsStdin {
                stdinData = try context.input.readAllData()
            }

            if let data = stdinData {
                parsed = try expandStdinValues(in: parsed, stdinData: data)
            }

            let resolvedRawBody = try resolveRawBody(options.rawBody, stdinData: stdinData)

            var payload = try RequestBuilder.build(
                from: parsed,
                bodyMode: options.bodyMode,
                rawBody: resolvedRawBody
            )

            if options.forceJSONAccept,
               let acceptName = HTTPField.Name("Accept"),
               RequestPayloadEncoding.shouldApplyDefaultHeader(named: acceptName, for: payload) {
                var headers = payload.request.headerFields
                headers[acceptName] = "application/json, */*;q=0.5"
                payload.request.headerFields = headers
            }

            if options.authProvided, let header = try authorizationHeader(for: options) {
                payload = applyAuthorization(header, to: payload)
            }

            let transportOptions = TransportOptions(
                timeout: options.timeout,
                verify: options.verify,
                httpVersionPreference: options.httpVersionPreference
            )

            let response = try context.transport.send(payload, options: transportOptions)
            let formatted = ResponseFormatter().format(response)
            context.console.out(formatted)
            return exitCode(for: response.response.status)
        } catch let error as CLIOptionError {
            context.console.error("error: \(error.cliDescription)\n")
            return ExitCode.usage.rawValue
        } catch let error as RequestParserError {
            context.console.error("error: \(error.cliDescription)\n")
            return ExitCode.usage.rawValue
        } catch let error as RequestBuilderError {
            context.console.error("error: \(error.cliDescription)\n")
            return ExitCode.usage.rawValue
        } catch let error as TransportError {
            context.console.error("transport error: \(error.cliDescription)\n")
            return ExitCode.failure.rawValue
        } catch {
            context.console.error("error: \(error.localizedDescription)\n")
            return ExitCode.failure.rawValue
        }
    }

    private func requiresStdin(parsed: ParsedRequest, rawBody: RawBodyInput?) -> Bool {
        if let rawBody, case .stdin = rawBody {
            return true
        }

        if parsed.items.headers.contains(where: { value in
            if case .stdin = value.value {
                return true
            }
            return false
        }) {
            return true
        }

        if parsed.items.data.contains(where: { field in
            switch field.value {
            case .textStdin, .jsonStdin:
                return true
            default:
                return false
            }
        }) {
            return true
        }

        return false
    }

    private func expandStdinValues(in request: ParsedRequest, stdinData: Data) throws -> ParsedRequest {
        var cachedText: String?
        var cachedJSON: JSONValue?

        func stdinText() -> String {
            if let cachedText {
                return cachedText
            }
            if let string = String(data: stdinData, encoding: .utf8) {
                cachedText = string
                return string
            }
            let decoded = String(decoding: stdinData, as: UTF8.self)
            cachedText = decoded
            return decoded
        }

        func stdinJSON() throws -> JSONValue {
            if let cachedJSON {
                return cachedJSON
            }
            do {
                let json = try JSONValue.parse(from: stdinData)
                cachedJSON = json
                return json
            } catch {
                let preview = String(data: stdinData, encoding: .utf8) ?? "<stdin>"
                throw RequestParserError.invalidJSON(preview)
            }
        }

        var headers: [HeaderField] = []
        headers.reserveCapacity(request.items.headers.count)

        for header in request.items.headers {
            switch header.value {
            case .stdin:
                headers.append(HeaderField(name: header.name, value: .some(stdinText())))
            default:
                headers.append(header)
            }
        }

        var dataFields: [DataField] = []
        dataFields.reserveCapacity(request.items.data.count)

        for field in request.items.data {
            switch field.value {
            case .textStdin:
                dataFields.append(DataField(name: field.name, value: .text(stdinText())))
            case .jsonStdin:
                dataFields.append(DataField(name: field.name, value: .json(try stdinJSON())))
            default:
                dataFields.append(field)
            }
        }

        let items = RequestItems(
            headers: headers,
            data: dataFields,
            query: request.items.query,
            files: request.items.files
        )

        return ParsedRequest(method: request.method, url: request.url, items: items)
    }

    private func resolveRawBody(_ input: RawBodyInput?, stdinData: Data?) throws -> RequestPayload.RawBody? {
        guard let input else {
            return nil
        }

        switch input {
        case .inline(let string):
            return .inline(string)
        case .file(let url):
            do {
                let data = try Data(contentsOf: url)
                return .data(data)
            } catch {
                throw RequestBuilderError.fileReadFailed(
                    url: url,
                    reason: "failed to read raw body file: \(error.localizedDescription)"
                )
            }
        case .stdin:
            guard let stdinData else {
                throw RequestBuilderError.stdinUnavailable("raw body")
            }
            return .data(stdinData)
        }
    }

    private var helpText: String {
        var lines: [String] = []

        lines.append(heading("SwiftPie"))
        lines.append("  Modern, Swift-native command-line HTTP client inspired by HTTPie.")
        lines.append("")

        lines.append(heading("Usage"))
        lines.append("  \(command("spie")) \(argument("[METHOD]")) \(argument("URL")) \(argument("[REQUEST_ITEM ...]"))")
        lines.append("")

        lines.append(heading("Positional Arguments"))
        lines.append(contentsOf: labeledBlock(
            label: "METHOD",
            details: [
                "Optional. \(command("spie")) infers GET unless data or file items are supplied; then POST is used.",
                "Supports standard verbs (GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS) and custom tokens."
            ]
        ))
        lines.append("")
        lines.append(contentsOf: labeledBlock(
            label: "URL",
            details: [
                "Required. Provide an absolute URL or use localhost shorthands like \(example(":/status/200")).",
                "Schemes default to http:// when omitted; use \(command("--ssl")) to prefer https://."
            ]
        ))
        lines.append("")
        lines.append(contentsOf: labeledBlock(
            label: "REQUEST_ITEM",
            details: [
                "Optional key/value tokens that become headers, query params, body data, or file uploads.",
                "\(separator(":")) headers — use a trailing colon to clear a header, e.g. \(example("Header:")).",
                "\(separator("==")) query parameters appended to the URL.",
                "\(separator("=")) data fields encoded as JSON by default (use --form for URL encoding).",
                "\(separator(":=")) JSON literals such as \(example("flag:=true")) or \(example("count:=42")).",
                "\(separator("@")) file uploads trigger multipart form data; \(separator("=@")) and \(separator(":=@")) embed text or JSON files; \(example("@-")) reads from stdin."
            ]
        ))
        lines.append("")

        lines.append(heading("Authentication"))
        lines.append(optionLine(flags: "-a, --auth CRED", description: "Send credentials (user:pass). Prompts if the password is omitted."))
        lines.append(optionLine(flags: "    --auth-type {basic|bearer}", description: "Select the authentication scheme; defaults to basic."))
        lines.append("")

        lines.append(heading("Body Modes"))
        lines.append(optionLine(flags: "-j, --json", description: "Explicitly select JSON mode (default) even when no data items are supplied."))
        lines.append(optionLine(flags: "-f, --form", description: "Send form-encoded data; file items switch to multipart automatically."))
        lines.append(optionLine(flags: "    --raw VALUE", description: "Bypass encoding and send raw body data (use VALUE, @file, or @- for stdin)."))
        lines.append("")

        lines.append(heading("Transport"))
        lines.append(optionLine(flags: "    --timeout SEC", description: "Set the request timeout in seconds (must be positive)."))
        lines.append(optionLine(flags: "    --verify [BOOL]", description: "Set to false (or no/0) to disable TLS verification; defaults to true."))
        lines.append(optionLine(flags: "    --http1", description: "Force HTTP/1.1 for the request."))
        lines.append(optionLine(flags: "    --ssl", description: "Switch the default scheme to https:// when no scheme is provided."))
        lines.append("")

        lines.append(heading("Input & Prompts"))
        lines.append(optionLine(flags: "-I, --ignore-stdin", description: "Skip reading stdin and disable interactive password prompts."))
        lines.append("")

        lines.append(heading("Help"))
        lines.append(optionLine(flags: "-h, --help", description: "Show this help message and exit."))
        lines.append("")

        lines.append("  Colors are disabled automatically when output is redirected.")

        return lines.joined(separator: "\n") + "\n"
    }

    private func heading(_ text: String) -> String {
        text.bold.green
    }

    private func command(_ text: String) -> String {
        text.bold
    }

    private func argument(_ text: String) -> String {
        text.cyan
    }

    private func separator(_ text: String) -> String {
        text.magenta
    }

    private func example(_ text: String) -> String {
        text.blue
    }

    private func labeledBlock(label: String, details: [String]) -> [String] {
        var lines: [String] = []
        lines.append("  \(labelStyle(label))")
        for detail in details {
            lines.append("    \(detail)")
        }
        return lines
    }

    private func optionLine(flags: String, description: String) -> String {
        let indentString = "  "
        let paddingWidth = 34
        let styledFlags = flagStyle(flags)
        let visibleCount = flags.count
        let paddingCount = max(1, paddingWidth - visibleCount)
        let padding = String(repeating: " ", count: paddingCount)
        return "\(indentString)\(styledFlags)\(padding)\(description)"
    }

    private func flagStyle(_ text: String) -> String {
        text.magenta
    }

    private func labelStyle(_ text: String) -> String {
        text.bold.green
    }

    private func exitCode(for status: HTTPResponse.Status) -> Int {
        switch status.code {
        case 100..<400:
            return ExitCode.success.rawValue
        default:
            return ExitCode.failure.rawValue
        }
    }

    private func authorizationHeader(for options: ParsedCLIOptions) throws -> String? {
        guard let rawValue = options.authValue else {
            return nil
        }

        switch options.authType {
        case .basic:
            let credential = try basicCredentialString(from: rawValue, options: options)
            guard let data = credential.data(using: .utf8) else {
                return nil
            }
            return "Basic \(data.base64EncodedString())"
        case .bearer:
            return "Bearer \(rawValue)"
        }
    }

    private func basicCredentialString(from rawValue: String, options: ParsedCLIOptions) throws -> String {
        if let separator = rawValue.firstIndex(of: ":") {
            let username = String(rawValue[..<separator])
            let passwordStart = rawValue.index(after: separator)
            let password = String(rawValue[passwordStart...])
            return "\(username):\(password)"
        }

        if options.ignoreStdin {
            throw CLIOptionError.passwordPromptUnavailable(.ignoreStdin)
        }

        guard context.input.isInteractive else {
            throw CLIOptionError.passwordPromptUnavailable(.nonInteractive)
        }

        let prompt = "Enter password for user '\(rawValue)': "
        context.console.error(prompt)
        guard let line = context.input.readSecureLine(prompt: prompt) else {
            context.console.error("\n")
            throw CLIOptionError.passwordPromptCancelled
        }

        let password = line.trimmingCharacters(in: CharacterSet.newlines)
        context.console.error("\n")
        return "\(rawValue):\(password)"
    }

    private func applyAuthorization(
        _ header: String,
        to payload: RequestPayload
    ) -> RequestPayload {
        guard let authorizationName = HTTPField.Name("Authorization") else {
            return payload
        }

        var updated = payload
        var request = updated.request
        var fields = request.headerFields
        fields[authorizationName] = header
        request.headerFields = fields
        updated.request = request
        updated.headerRemovals.removeAll { $0 == authorizationName }
        return updated
    }
}
