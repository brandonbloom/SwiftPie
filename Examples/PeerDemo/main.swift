import Foundation
import SwiftPie
import SwiftPieTestSupport

@main
struct PeerDemo {
    static func main() {
        let baseURL = URL(string: "http://peer.local")!
        let responder = TestPeerResponder.makePeerResponder(baseURL: baseURL)
        let transport = PeerTransport(responder: responder)
        let context = CLIContext(
            transport: transport,
            parserOptions: RequestParserOptions(baseURL: baseURL)
        )

        SwiftPie.main(arguments: CommandLine.arguments, context: context)
    }
}
