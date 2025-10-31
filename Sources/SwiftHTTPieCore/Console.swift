import Foundation

public enum ConsoleStream {
    case standardOutput
    case standardError
}

public protocol Console: Sendable {
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

public struct StandardConsole: Console {
    public init() {}

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
