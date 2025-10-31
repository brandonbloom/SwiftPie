#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

import Foundation
import HTTPTypes

public enum SwiftHTTPie {
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
}

private struct OptionParser {
    var arguments: [String]

    func parse() throws -> ParsedCLIOptions {
        var remaining: [String] = []
        var showHelp = false
        var parsingOptions = true

        for argument in arguments {
            if parsingOptions {
                if argument == "--" {
                    parsingOptions = false
                    continue
                }

                if argument.hasPrefix("-"), argument != "-" {
                    switch argument {
                    case "-h", "--help":
                        showHelp = true
                        continue
                    default:
                        throw CLIOptionError.unknownOption(argument)
                    }
                }
            }

            remaining.append(argument)
        }

        return ParsedCLIOptions(
            showHelp: showHelp,
            arguments: remaining
        )
    }
}

private enum CLIOptionError: Error {
    case unknownOption(String)
}

private extension CLIOptionError {
    var cliDescription: String {
        switch self {
        case .unknownOption(let option):
            return "unknown option '\(option)'"
        }
    }
}

public struct CLIContext<Transport: RequestTransport> {
    public var console: any Console
    public var transport: Transport

    public init(
        console: any Console = StandardConsole(),
        transport: Transport
    ) {
        self.console = console
        self.transport = transport
    }
}

public extension CLIContext where Transport == URLSessionTransport {
    init(console: any Console = StandardConsole(), transport: Transport = URLSessionTransport()) {
        self.console = console
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

            let parsed = try RequestParser.parse(arguments: options.arguments)
            let payload = try RequestBuilder.build(from: parsed)
            let response = try context.transport.send(payload)
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
        usage: SwiftHTTPie [options] <HTTP request parts>

        options:
          -h, --help     Show this help message and exit.

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
}
