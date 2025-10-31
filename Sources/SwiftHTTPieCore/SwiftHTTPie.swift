#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

import Foundation

public enum SwiftHTTPie {
    /// Primary entry point invoked by the CLI executable.
    /// - Parameter arguments: The raw command-line arguments, usually `CommandLine.arguments`.
    /// - Returns: Never returns because it terminates the process with the exit code.
    public static func main(arguments: [String]) -> Never {
        let exitCode = run(arguments: arguments)
        exit(Int32(exitCode))
    }

    /// Utility that executes the CLI flow and returns an exit status.
    /// Allows callers (like the executable target) to handle process termination.
    public static func run(arguments: [String], environment: CLIEnvironment = .init()) -> Int {
        let runner = CLIRunner(arguments: arguments, environment: environment)
        return runner.run()
    }
}

public struct CLIEnvironment {
    public var console: any Console
    public var requestSink: (RequestPayload) -> Void

    public init(
        console: any Console = StandardConsole(),
        requestSink: @escaping (RequestPayload) -> Void = { _ in }
    ) {
        self.console = console
        self.requestSink = requestSink
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

private struct CLIRunner {
    private let arguments: [String]
    private let environment: CLIEnvironment

    init(arguments: [String], environment: CLIEnvironment) {
        self.arguments = arguments
        self.environment = environment
    }

    func run() -> Int {
        let userArguments = Array(arguments.dropFirst())

        if shouldShowHelp(userArguments) {
            environment.console.out(helpText)
            return ExitCode.success.rawValue
        }

        do {
            let parsed = try RequestParser.parse(arguments: userArguments)
            let payload = try RequestBuilder.build(from: parsed)
            environment.requestSink(payload)
            environment.console.out("Request prepared. Transport integration pending.\n")
            return ExitCode.success.rawValue
        } catch let error as RequestParserError {
            environment.console.error("error: \(error.cliDescription)\n")
            return ExitCode.usage.rawValue
        } catch let error as RequestBuilderError {
            environment.console.error("error: \(error.cliDescription)\n")
            return ExitCode.usage.rawValue
        } catch {
            environment.console.error("error: \(error.localizedDescription)\n")
            return ExitCode.failure.rawValue
        }
    }

    private func shouldShowHelp(_ userArguments: [String]) -> Bool {
        guard !userArguments.isEmpty else {
            return true
        }

        return userArguments.contains { argument in
            argument == "--help" || argument == "-h"
        }
    }

    private var helpText: String {
        """
        usage: SwiftHTTPie [options] <HTTP request parts>

        options:
          -h, --help     Show this help message and exit.

        """
    }
}
