import Foundation
import SwiftPie
import SwiftPieTestSupport

@main
struct PeerDemo {
    static func main() {
        let baseURL = URL(string: "http://peer.local")!
        let responder = TestPeerResponder.makePeerResponder(baseURL: baseURL)
        SwiftPie.main(parserOptions: RequestParserOptions(baseURL: baseURL), responder: responder)
    }
}
