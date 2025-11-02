import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum ConsoleStream {
    case standardOutput
    case standardError
}

public protocol Console: AnyObject {
    var isOutputTerminal: Bool { get }
    func write(_ text: String, to stream: ConsoleStream)
}

public extension Console {
    func out(_ text: String) {
        write(text, to: .standardOutput)
    }

    func error(_ text: String) {
        write(text, to: .standardError)
    }
}

public final class StandardConsole: Console {
    public let isOutputTerminal: Bool

    public init() {
        #if canImport(Darwin)
        isOutputTerminal = isatty(STDOUT_FILENO) != 0
        #else
        isOutputTerminal = isatty(STDOUT_FILENO) != 0
        #endif
    }

    public func write(_ text: String, to stream: ConsoleStream) {
        guard let data = text.data(using: .utf8) else { return }
        switch stream {
        case .standardOutput:
            FileHandle.standardOutput.write(data)
        case .standardError:
            FileHandle.standardError.write(data)
        }
    }
}

/// Console wrapper that suppresses output based on quiet level
internal final class QuietConsole: Console {
    private let underlying: any Console
    private let suppressStdout: Bool
    private let suppressStderr: Bool
    let isOutputTerminal: Bool

    internal init(underlying: any Console, suppressStdout: Bool, suppressStderr: Bool) {
        self.underlying = underlying
        self.suppressStdout = suppressStdout
        self.suppressStderr = suppressStderr
        self.isOutputTerminal = underlying.isOutputTerminal
    }

    internal func write(_ text: String, to stream: ConsoleStream) {
        switch stream {
        case .standardOutput:
            if !suppressStdout {
                underlying.write(text, to: stream)
            }
        case .standardError:
            if !suppressStderr {
                underlying.write(text, to: stream)
            }
        }
    }
}
