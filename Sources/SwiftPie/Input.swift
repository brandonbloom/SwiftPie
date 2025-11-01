#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

import Foundation

public protocol InputSource {
    var isInteractive: Bool { get }
    func readSecureLine(prompt: String) -> String?
    func readAllData() throws -> Data
}

public final class StandardInput: InputSource {
    public init() {}

    public var isInteractive: Bool {
        isatty(fileno(stdin)) != 0
    }

    public func readSecureLine(prompt: String) -> String? {
        let fileDescriptor = fileno(stdin)

        guard isatty(fileDescriptor) != 0 else {
            return readLine()
        }

        var originalSettings = termios()
        if tcgetattr(fileDescriptor, &originalSettings) != 0 {
            return readLine()
        }

        var noEchoSettings = originalSettings
        noEchoSettings.c_lflag &= ~tcflag_t(ECHO)

        if tcsetattr(fileDescriptor, TCSAFLUSH, &noEchoSettings) != 0 {
            _ = tcsetattr(fileDescriptor, TCSAFLUSH, &originalSettings)
            return readLine()
        }

        defer {
            _ = tcsetattr(fileDescriptor, TCSAFLUSH, &originalSettings)
        }

        return readLine()
    }

    public func readAllData() throws -> Data {
        let handle = FileHandle.standardInput
        guard let data = try handle.readToEnd() else {
            return Data()
        }
        return data
    }
}
