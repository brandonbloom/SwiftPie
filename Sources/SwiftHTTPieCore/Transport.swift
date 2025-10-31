import Foundation
import HTTPTypes

public protocol RequestTransport {
    func send(_ payload: RequestPayload) throws -> ResponsePayload
}

public struct ResponsePayload: Equatable, Sendable {
    public var response: HTTPResponse
    public var body: ResponseBody

    public init(response: HTTPResponse, body: ResponseBody) {
        self.response = response
        self.body = body
    }
}

public enum ResponseBody: Equatable, Sendable {
    case none
    case text(String)
    case data(Data)
}

public enum TransportError: Error, Equatable, Sendable {
    case networkError(String)
    case internalFailure(String)
}

extension TransportError {
    var cliDescription: String {
        switch self {
        case .networkError(let message),
             .internalFailure(let message):
            return message
        }
    }
}

public struct PendingTransport: RequestTransport {
    public init() {}

    public func send(_ payload: RequestPayload) throws -> ResponsePayload {
        ResponsePayload(
            response: HTTPResponse(status: .ok),
            body: .text("Transport integration pending.")
        )
    }
}
