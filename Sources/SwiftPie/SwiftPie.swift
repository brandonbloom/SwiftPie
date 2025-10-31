#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

import Foundation
import HTTPTypes

public enum SwiftPie {
    /// Primary entry point invoked by the CLI executable.
    /// - Parameter arguments: The raw command-line arguments, usually `CommandLine.arguments`.
    /// - Returns: Never returns because it terminates the process with the exit code.
    public static func main(arguments: [String]) -> Never {
        let exitCode = run(arguments: arguments)
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
}

private enum AuthType {
    case basic
    case bearer
}

private enum PromptUnavailableReason {
    case ignoreStdin
    case nonInteractive
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
                    case "--http1":
                        httpVersionPreference = .http1Only
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
            httpVersionPreference: httpVersionPreference
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
        }
    }
}

public struct CLIContext<Transport: RequestTransport> {
    public var console: any Console
    public var input: any InputSource
    public var transport: Transport

    public init(
        console: any Console = StandardConsole(),
        input: any InputSource = StandardInput(),
        transport: Transport
    ) {
        self.console = console
        self.input = input
        self.transport = transport
    }
}

public extension CLIContext where Transport == URLSessionTransport {
    init(
        console: any Console = StandardConsole(),
        input: any InputSource = StandardInput(),
        transport: Transport = URLSessionTransport()
    ) {
        self.console = console
        self.input = input
        self.transport = transport
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

            let parsed = try RequestParser.parse(arguments: options.arguments)
            var payload = try RequestBuilder.build(from: parsed)

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

    private var helpText: String {
        """
        usage: spie [options] <HTTP request parts>

        options:
          -h, --help          Show this help message and exit.
          -a, --auth CRED     Send credentials (user:pass). Prompts if password missing.
              --auth-type T   Authentication scheme (basic, bearer).
              --timeout SEC   Set request timeout in seconds.
              --verify [BOOL] Toggle TLS verification (use --verify=false to disable).
              --http1         Force HTTP/1.1 for the request.
          -I, --ignore-stdin  Do not read stdin or prompt for passwords.

        """
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
