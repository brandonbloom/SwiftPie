import Foundation
import HTTPTypes
import Testing
@testable import SwiftHTTPie

@Suite("Peer transport")
struct PeerTransportTests {
    final class RequestCapture: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: PeerRequest?

        func set(_ request: PeerRequest) {
            lock.lock()
            storage = request
            lock.unlock()
        }

        func get() -> PeerRequest? {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    @Test("Encodes request payloads before invoking responder")
    func encodesPayloads() throws {
        let capture = RequestCapture()

        let transport = PeerTransport { request in
            capture.set(request)

            let response = HTTPResponse(status: .ok)
            return ResponsePayload(response: response, body: .text("ok"))
        }

        let parsed = try RequestParser.parse(arguments: [
            "POST",
            "http://example.local/post",
            "foo=bar"
        ])

        let payload = try RequestBuilder.build(from: parsed)
        let response = try transport.send(payload, options: TransportOptions())

        #expect(response.response.status == .ok)

        let request = try #require(capture.get())
        #expect(request.request.method == .post)
        #expect(request.request.path == "/post")

        if let contentType = HTTPField.Name("Content-Type") {
            #expect(request.request.headerFields[contentType] == "application/x-www-form-urlencoded; charset=utf-8")
        }

        guard case .data(let bodyData) = request.body else {
            Issue.record("Expected encoded body data")
            return
        }

        let bodyString = String(data: bodyData, encoding: .utf8)
        #expect(bodyString == "foo=bar")
    }

    @Test("Keeps explicit headers and respects header removals")
    func keepsExplicitHeaders() throws {
        let capture = RequestCapture()

        let transport = PeerTransport { request in
            capture.set(request)
            return ResponsePayload(response: HTTPResponse(status: .ok), body: .none)
        }

        let parsed = try RequestParser.parse(arguments: [
            "POST",
            "http://example.local/post",
            "Content-Type:application/json",
            "foo:=true"
        ])

        let payload = try RequestBuilder.build(from: parsed)
        _ = try transport.send(payload, options: TransportOptions(httpVersionPreference: .http1Only))

        let request = try #require(capture.get())

        if let contentType = HTTPField.Name("Content-Type") {
            #expect(request.request.headerFields[contentType] == "application/json")
        }

        if let connection = HTTPField.Name("Connection") {
            #expect(request.request.headerFields[connection] == "close")
        }
    }

    @Test("Transforms responder errors into transport failures")
    func transformsResponderErrors() throws {
        let transport = PeerTransport { _ in
            struct SampleError: Error {}
            throw SampleError()
        }

        let parsed = try RequestParser.parse(arguments: [
            "http://example.local/get"
        ])

        let payload = try RequestBuilder.build(from: parsed)

        do {
            _ = try transport.send(payload, options: TransportOptions())
            Issue.record("Expected transport error")
        } catch let error as TransportError {
            switch error {
            case .internalFailure(let message):
                #expect(message.isEmpty == false)
            default:
                Issue.record("Expected internal failure, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
