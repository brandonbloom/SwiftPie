import Foundation
import HTTPTypes

public protocol RequestTransport {
    func send(_ payload: RequestPayload, options: TransportOptions) throws -> ResponsePayload
}

public struct TransportOptions: Equatable, Sendable {
    public enum TLSVerification: Equatable, Sendable {
        case enforced
        case disabled
    }

    public enum HTTPVersionPreference: Equatable, Sendable {
        case automatic
        case http1Only
    }

    public var timeout: TimeInterval?
    public var verify: TLSVerification
    public var httpVersionPreference: HTTPVersionPreference

    public init(
        timeout: TimeInterval? = nil,
        verify: TLSVerification = .enforced,
        httpVersionPreference: HTTPVersionPreference = .automatic
    ) {
        self.timeout = timeout
        self.verify = verify
        self.httpVersionPreference = httpVersionPreference
    }
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
