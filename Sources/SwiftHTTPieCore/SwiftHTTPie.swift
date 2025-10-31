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
    @discardableResult
    public static func run(arguments: [String]) -> Int {
        let runner = CLIRunner(arguments: arguments)
        return runner.run()
    }
}

private struct CLIRunner {
    private let arguments: [String]

    init(arguments: [String]) {
        self.arguments = arguments
    }

    func run() -> Int {
        let userArguments = Array(arguments.dropFirst())

        if shouldShowHelp(userArguments) {
            Console.standardOut.write(helpText)
            return 0
        }

        // Placeholder: future phases will parse the user arguments into HTTP requests.
        Console.standardOut.write("SwiftHTTPie is under construction.\n")

        if !userArguments.isEmpty {
            let joinedArguments = userArguments.joined(separator: " ")
            Console.standardOut.write("Arguments: \(joinedArguments)\n")
        }
        return 0
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

private struct Console {
    static let standardOut = Console(handle: .standardOutput)
    static let standardError = Console(handle: .standardError)

    private let handle: FileHandle

    init(handle: FileHandle) {
        self.handle = handle
    }

    func write(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        handle.write(data)
    }
}
