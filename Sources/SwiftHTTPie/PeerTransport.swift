import Foundation
import HTTPTypes

/// The body delivered to a peer responder.
///
/// When the originating CLI payload carries data, the transport encodes it the
/// same way the real network transport would (form URL encoded, JSON, or
/// multipart) before making it available through this enum.
public enum PeerRequestBody: Sendable {
    case none
    case data(Data)

    /// Returns the raw body data if present.
    public var data: Data? {
        switch self {
        case .none:
            return nil
        case .data(let data):
            return data
        }
    }

    /// Decodes the body into a string using the supplied encoding.
    public func string(encoding: String.Encoding = .utf8) -> String? {
        guard case .data(let data) = self else {
            return nil
        }
        return String(data: data, encoding: encoding)
    }
}

/// Metadata describing a request destined for a peer responder.
public struct PeerRequest: Sendable {
    public var request: HTTPRequest
    public var body: PeerRequestBody
    public var options: TransportOptions

    /// Creates a new peer request wrapper.
    public init(
        request: HTTPRequest,
        body: PeerRequestBody,
        options: TransportOptions
    ) {
        self.request = request
        self.body = body
        self.options = options
    }
}

/// Signature for responders that operate entirely in-process instead of
/// issuing network requests.
public typealias PeerResponder = @Sendable (PeerRequest) async throws -> ResponsePayload

/// A transport implementation that forwards CLI requests to an in-process
/// responder instead of performing real network I/O.
public final class PeerTransport: RequestTransport {
    private let responder: PeerResponder

    /// Creates a transport backed by the provided responder closure.
    ///
    /// - Parameter responder: Asynchronous closure that receives the encoded
    ///   request and returns a response payload.
    public init(responder: @escaping PeerResponder) {
        self.responder = responder
    }

    public func send(
        _ payload: RequestPayload,
        options: TransportOptions
    ) throws -> ResponsePayload {
        let peerRequest = try makePeerRequest(from: payload, options: options)

        final class ResultBox: @unchecked Sendable {
            var value: Result<ResponsePayload, Error>?
        }

        let semaphore = DispatchSemaphore(value: 0)
        let result = ResultBox()

        let handler = responder

        Task {
            defer { semaphore.signal() }
            do {
                let response = try await handler(peerRequest)
                result.value = .success(response)
            } catch {
                result.value = .failure(error)
            }
        }

        semaphore.wait()

        guard let resolved = result.value else {
            throw TransportError.internalFailure("peer responder did not produce a result")
        }

        switch resolved {
        case .success(let response):
            return response
        case .failure(let error):
            if let transportError = error as? TransportError {
                throw transportError
            }
            throw TransportError.internalFailure(error.localizedDescription)
        }
    }

    private func makePeerRequest(
        from payload: RequestPayload,
        options: TransportOptions
    ) throws -> PeerRequest {
        var request = payload.request
        var body: PeerRequestBody = .none

        if let encodedBody = try RequestPayloadEncoding.encodeBody(from: payload) {
            body = .data(encodedBody.data)

            if let contentType = encodedBody.contentType,
               let fieldName = HTTPField.Name("Content-Type"),
               RequestPayloadEncoding.shouldApplyDefaultHeader(named: fieldName, for: payload) {
                var headers = request.headerFields
                headers[fieldName] = contentType
                request.headerFields = headers
            }
        }

        if options.httpVersionPreference == .http1Only,
           let fieldName = HTTPField.Name("Connection"),
           RequestPayloadEncoding.shouldApplyDefaultHeader(named: fieldName, for: payload) {
            var headers = request.headerFields
            headers[fieldName] = "close"
            request.headerFields = headers
        }

        return PeerRequest(request: request, body: body, options: options)
    }
}
