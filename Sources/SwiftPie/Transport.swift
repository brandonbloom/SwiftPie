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

public struct AnyRequestTransport: RequestTransport {
    private let box: TransportBox

    public init<Wrapped: RequestTransport>(_ wrapped: Wrapped) {
        if let existing = wrapped as? AnyRequestTransport {
            self = existing
            return
        }
        self.box = TransportConcreteBox(wrapped)
    }

    public func send(_ payload: RequestPayload, options: TransportOptions) throws -> ResponsePayload {
        try box.send(payload, options: options)
    }
}

private class TransportBox {
    func send(_ payload: RequestPayload, options: TransportOptions) throws -> ResponsePayload {
        fatalError("Must override")
    }
}

private final class TransportConcreteBox<Wrapped: RequestTransport>: TransportBox {
    private let wrapped: Wrapped

    init(_ wrapped: Wrapped) {
        self.wrapped = wrapped
    }

    override func send(_ payload: RequestPayload, options: TransportOptions) throws -> ResponsePayload {
        try wrapped.send(payload, options: options)
    }
}

public struct TransportID: RawRepresentable, Hashable, Equatable, Sendable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

public extension TransportID {
    static let foundation = TransportID("foundation")
    static let nio = TransportID("nio")
}

public struct TransportCapabilities: OptionSet, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let supportsTLSVerificationToggle = TransportCapabilities(rawValue: 1 << 0)
    public static let supportsHTTP2 = TransportCapabilities(rawValue: 1 << 1)
    public static let supportsStreamingUpload = TransportCapabilities(rawValue: 1 << 2)
    public static let supportsStreamingDownload = TransportCapabilities(rawValue: 1 << 3)
    public static let supportsCookies = TransportCapabilities(rawValue: 1 << 4)
    public static let supportsPeerMode = TransportCapabilities(rawValue: 1 << 5)
}

public enum TransportKind: Equatable, Sendable {
    case runtimeSelectable
    case peerOnly
}

public struct TransportDescriptor: Sendable {
    public let id: TransportID
    public let label: String
    public let kind: TransportKind
    public let capabilities: TransportCapabilities
    private let availabilityCheck: @Sendable () -> Bool
    private let factory: @Sendable () throws -> AnyRequestTransport

    public init(
        id: TransportID,
        label: String,
        kind: TransportKind,
        capabilities: TransportCapabilities,
        isSupported: @escaping @Sendable () -> Bool,
        makeTransport: @escaping @Sendable () throws -> AnyRequestTransport
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.capabilities = capabilities
        self.availabilityCheck = isSupported
        self.factory = makeTransport
    }

    public func isSupported() -> Bool {
        availabilityCheck()
    }

    public func makeTransport() throws -> AnyRequestTransport {
        try factory()
    }
}

public enum TransportRegistryError: Error, Equatable, Sendable {
    case unknownTransport(String)
    case transportUnavailable(String)
    case noTransportsAvailable
}

public struct TransportRegistry: Sendable {
    public var defaultID: TransportID
    private var descriptorsByID: [TransportID: TransportDescriptor]

    public init(defaultID: TransportID, descriptors: [TransportDescriptor]) {
        self.defaultID = defaultID
        var mapping: [TransportID: TransportDescriptor] = [:]
        for descriptor in descriptors {
            mapping[descriptor.id] = descriptor
        }
        self.descriptorsByID = mapping
    }

    public func descriptor(for id: TransportID) -> TransportDescriptor? {
        descriptorsByID[id]
    }

    public func runtimeSelectableDescriptors() -> [TransportDescriptor] {
        descriptorsByID.values
            .filter { $0.kind == .runtimeSelectable && $0.isSupported() }
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }

    public func selectableIdentifiers() -> [TransportID] {
        runtimeSelectableDescriptors().map(\.id)
    }

    public func resolveDefaultID() -> TransportID? {
        if let descriptor = descriptor(for: defaultID), descriptor.isSupported() {
            return descriptor.id
        }

        return runtimeSelectableDescriptors().first?.id
    }

    public func makeTransport(for id: TransportID) throws -> AnyRequestTransport {
        guard let descriptor = descriptor(for: id) else {
            throw TransportRegistryError.unknownTransport(id.rawValue)
        }

        guard descriptor.isSupported() else {
            throw TransportRegistryError.transportUnavailable(id.rawValue)
        }

        return try descriptor.makeTransport()
    }

    public func makeDefaultTransport() throws -> AnyRequestTransport {
        guard let resolved = resolveDefaultID() else {
            throw TransportRegistryError.noTransportsAvailable
        }

        return try makeTransport(for: resolved)
    }
}

public extension TransportRegistry {
    static var standard: TransportRegistry {
        TransportRegistry(
            defaultID: .foundation,
            descriptors: [
                .foundation(),
                .nio()
            ]
        )
    }
}

private extension TransportDescriptor {
    static func foundation() -> TransportDescriptor {
        let capabilities: TransportCapabilities = {
            var value: TransportCapabilities = [
                .supportsHTTP2,
                .supportsStreamingDownload,
                .supportsStreamingUpload,
                .supportsCookies
            ]
#if canImport(Darwin)
            value.insert(.supportsTLSVerificationToggle)
#endif
            return value
        }()

        return TransportDescriptor(
            id: .foundation,
            label: "FoundationNetworking (URLSession)",
            kind: .runtimeSelectable,
            capabilities: capabilities,
            isSupported: {
                true
            },
            makeTransport: {
                AnyRequestTransport(URLSessionTransport())
            }
        )
    }

    static func nio() -> TransportDescriptor {
        let capabilities: TransportCapabilities = [
            .supportsTLSVerificationToggle
        ]

        return TransportDescriptor(
            id: .nio,
            label: "SwiftNIO HTTP/1.1",
            kind: .runtimeSelectable,
            capabilities: capabilities,
            isSupported: {
                true
            },
            makeTransport: {
                AnyRequestTransport(NIOHTTPTransport())
            }
        )
    }
}
