import Foundation
import HTTPTypes
import SwiftHTTPie
import SwiftHTTPieTestSupport

@main
struct PeerDemo {
    static func main() {
        let baseURL = URL(string: "http://peer.local")!
        let responder = TestPeerResponder.makePeerResponder(baseURL: baseURL)
        let transport = PeerTransport(responder: responder)
        let context = CLIContext(transport: transport)

        let normalizedArguments = normalize(CommandLine.arguments, baseURL: baseURL)
        let exitCode = SwiftHTTPie.run(arguments: normalizedArguments, context: context)
        exit(Int32(exitCode))
    }

    private static func normalize(_ arguments: [String], baseURL: URL) -> [String] {
        guard arguments.count > 1 else {
            return arguments
        }

        var result = arguments
        var userArguments = Array(result.dropFirst())
        var targetIndex = 0

        if HTTPRequest.Method(rawValue: userArguments.first?.uppercased() ?? "") != nil {
            targetIndex = 1
        }

        if targetIndex < userArguments.count {
            let candidate = userArguments[targetIndex]
            if !candidate.contains("://") {
                let prefixed = candidate.hasPrefix("/") ? candidate : "/\(candidate)"
                if let url = URL(string: prefixed, relativeTo: baseURL) {
                    userArguments[targetIndex] = url.absoluteString
                }
            }
        }

        result.replaceSubrange(result.indices.dropFirst(), with: userArguments)
        return result
    }
}
