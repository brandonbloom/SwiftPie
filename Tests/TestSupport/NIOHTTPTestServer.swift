import Foundation
import NIO
import NIOConcurrencyHelpers
import NIOHTTP1
import NIOPosix
import SwiftPie

// MARK: - Public API

public struct TestServerConfiguration: Sendable {
    public var host: String
    public var port: Int?
    public var useTLS: Bool

    public init(host: String = "127.0.0.1", port: Int? = nil, useTLS: Bool = false) {
        self.host = host
        self.port = port
        self.useTLS = useTLS
    }

    public static let standard = TestServerConfiguration()
}

public struct CapturedRequest: Sendable {
    public struct Header: Sendable {
        public var name: String
        public var value: String
    }

    public var method: NIOHTTP1.HTTPMethod
    public var uri: String
    public var path: String
    public var queryParameters: [String: [String]]
    public var headers: [Header]
    public var body: Data

    public func headerValues(for name: String) -> [String] {
        headers.compactMap { header in
            header.name.caseInsensitiveCompare(name) == .orderedSame ? header.value : nil
        }
    }
}

public struct TestServerHandle {
    private let server: NIOHTTPTestServer

    init(server: NIOHTTPTestServer) {
        self.server = server
    }

    public var baseURL: URL {
        server.baseURL
    }

    public func stop() throws {
        try server.shutdown()
    }

    public func recordedRequests(path: String? = nil) -> [CapturedRequest] {
        server.recorder.requests(matching: path)
    }

    public func lastRequest(path: String) -> CapturedRequest? {
        recordedRequests(path: path).last
    }
}

public func withTestServer<R>(
    configuration: TestServerConfiguration = .standard,
    _ body: (TestServerHandle) throws -> R
) throws -> R {
    let server = try NIOHTTPTestServer.start(configuration: configuration)

    let handle = TestServerHandle(server: server)
    do {
        let result = try body(handle)
        try server.shutdown()
        return result
    } catch {
        try? server.shutdown()
        throw error
    }
}

@discardableResult
public func withTestServer<R>(
    configuration: TestServerConfiguration = .standard,
    _ body: (TestServerHandle) async throws -> R
) async throws -> R {
    let server = try NIOHTTPTestServer.start(configuration: configuration)

    let handle = TestServerHandle(server: server)
    do {
        let result = try await body(handle)
        try server.shutdown()
        return result
    } catch {
        try? server.shutdown()
        throw error
    }
}

// MARK: - Server implementation

final class NIOHTTPTestServer {
    let baseURL: URL
    let configuration: TestServerConfiguration
    let recorder: RequestRecorder

    private let group: EventLoopGroup
    private let channel: Channel
    private let router: TestServerRouter

    private init(
        baseURL: URL,
        configuration: TestServerConfiguration,
        recorder: RequestRecorder,
        group: EventLoopGroup,
        channel: Channel,
        router: TestServerRouter
    ) {
        self.baseURL = baseURL
        self.configuration = configuration
        self.recorder = recorder
        self.group = group
        self.channel = channel
        self.router = router
    }

    static func start(configuration: TestServerConfiguration) throws -> NIOHTTPTestServer {
        precondition(configuration.useTLS == false, "TLS support not implemented yet.")

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let recorder = RequestRecorder()
        let router = TestServerRouter(recorder: recorder)

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.socketOption(.tcp_nodelay), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(ServerLifecycleHandler()).flatMap {
                    channel.pipeline.configureHTTPServerPipeline()
                }.flatMap {
                    channel.pipeline.addHandler(HTTPRequestHandler(router: router))
                }
            }

        let channel = try bootstrap.bind(host: configuration.host, port: configuration.port ?? 0).wait()
        guard let localAddress = channel.localAddress, let port = localAddress.port else {
            throw TestServerError.unableToDetermineLocalAddress
        }

        let baseURL = URL(string: "http://\(configuration.host):\(port)")!

        let server = NIOHTTPTestServer(
            baseURL: baseURL,
            configuration: configuration,
            recorder: recorder,
            group: group,
            channel: channel,
            router: router
        )

        router.baseURL = baseURL
        return server
    }

    func shutdown() throws {
        try channel.close().wait()
        try group.syncShutdownGracefully()
    }
}

enum TestServerError: Error {
    case unableToDetermineLocalAddress
}

// MARK: - Request Recording

final class RequestRecorder: @unchecked Sendable {
    private let storage = NIOLockedValueBox<[CapturedRequest]>([])

    func record(_ request: CapturedRequest) {
        storage.withLockedValue { buffer in
            buffer.append(request)
        }
    }

    func requests(matching path: String?) -> [CapturedRequest] {
        storage.withLockedValue { buffer in
            guard let path else { return buffer }
            return buffer.filter { $0.path == path }
        }
    }
}

// MARK: - Router

final class TestServerRouter: @unchecked Sendable {
    private let recorder: RequestRecorder
    private let allocator = ByteBufferAllocator()
    var baseURL: URL?

    init(recorder: RequestRecorder) {
        self.recorder = recorder
    }

    func handle(
        request: CapturedRequest,
        head: HTTPRequestHead
    ) -> TestServerResponse {
        recorder.record(request)

        let resolvedBase = baseURL ?? URL(string: "http://127.0.0.1")!
        let payload = TestPeerResponder.respond(to: request, head: head, baseURL: resolvedBase)
        return TestServerResponse.from(payload, allocator: allocator)
    }
}

// MARK: - Utilities

private extension CapturedRequest {
    var singleValueQuery: [String: String] {
        queryParameters.reduce(into: [:]) { partialResult, entry in
            partialResult[entry.key] = entry.value.last ?? ""
        }
    }

    var headerDictionary: [String: String] {
        headers.reduce(into: [:]) { result, header in
            result[header.name] = header.value
        }
    }

    var formPayload: [String: String] {
        guard let string = String(data: body, encoding: .utf8) else {
            return [:]
        }
        return string
            .split(separator: "&")
            .reduce(into: [:]) { result, pair in
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return }
                let name = parts[0].removingPercentEncoding ?? parts[0]
                let value = parts[1].removingPercentEncoding ?? parts[1]
                result[name] = value
            }
    }

    var cookies: [String: String] {
        guard let cookieHeader = headerValues(for: "Cookie").last else {
            return [:]
        }

        return cookieHeader
            .split(separator: ";")
            .reduce(into: [:]) { partialResult, pair in
                let parts = pair.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }

                guard parts.count == 2 else { return }
                partialResult[parts[0]] = parts[1]
            }
    }

    func fullURL(baseURL: URL?) -> String {
        if let baseURL {
            return baseURL.appendingPathComponent(path).absoluteString
        }

        return pathWithQuery
    }

    var pathWithQuery: String {
        guard let query = queryString else { return path }
        return "\(path)?\(query)"
    }

    private var queryString: String? {
        guard !queryParameters.isEmpty else { return nil }
        return queryParameters
            .sorted(by: { $0.key < $1.key })
            .flatMap { key, values in
                values.map { value in
                    let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                    let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                    return "\(encodedKey)=\(encodedValue)"
                }
            }
            .joined(separator: "&")
    }
}

// MARK: - Response modeling

struct TestServerResponse {
    enum Body {
        case empty
        case buffer(ByteBuffer)
    }

    var status: HTTPResponseStatus
    var headers: HTTPHeaders
    var body: Body

    static func from(
        _ payload: ResponsePayload,
        allocator: ByteBufferAllocator
    ) -> TestServerResponse {
        let status = HTTPResponseStatus(statusCode: payload.response.status.code)

        var headers = HTTPHeaders()
        for field in payload.response.headerFields {
            headers.add(name: field.name.rawName, value: field.value)
        }

        let body: Body
        switch payload.body {
        case .none:
            body = .empty
        case .text(let string):
            var buffer = allocator.buffer(capacity: string.utf8.count)
            buffer.writeString(string)
            body = .buffer(buffer)
        case .data(let data):
            var buffer = allocator.buffer(capacity: data.count)
            buffer.writeBytes(data)
            body = .buffer(buffer)
        }

        return TestServerResponse(
            status: status,
            headers: headers,
            body: body
        )
    }
}

// MARK: - Channel Handler

final class HTTPRequestHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let router: TestServerRouter

    private var currentHead: HTTPRequestHead?
    private var bodyBuffer: ByteBuffer?

    init(router: TestServerRouter) {
        self.router = router
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            currentHead = head
            bodyBuffer = context.channel.allocator.buffer(capacity: 0)

        case .body(var chunk):
            if bodyBuffer == nil {
                bodyBuffer = chunk
            } else {
                bodyBuffer?.writeBuffer(&chunk)
            }

        case .end:
            guard let head = currentHead else {
                return
            }

            var buffer = bodyBuffer ?? context.channel.allocator.buffer(capacity: 0)
            currentHead = nil
            bodyBuffer = nil

            let captured = CapturedRequest.make(from: head, bodyBuffer: &buffer)
            let response = router.handle(request: captured, head: head)
            _ = write(response, requestHead: head, context: context)
        }
    }

    private func write(
        _ response: TestServerResponse,
        requestHead: HTTPRequestHead,
        context: ChannelHandlerContext
    ) -> EventLoopFuture<Void> {
        var headers = response.headers
        var bodyBuffer: ByteBuffer?

        switch response.body {
        case .empty:
            if !headers.contains(name: "Content-Length") {
                headers.add(name: "Content-Length", value: "0")
            }
        case .buffer(let buffer):
            bodyBuffer = buffer
            if !headers.contains(name: "Content-Length") {
                headers.add(name: "Content-Length", value: "\(buffer.readableBytes)")
            }
        }

        let head = HTTPResponseHead(version: requestHead.version, status: response.status, headers: headers)

        context.write(wrapOutboundOut(.head(head)), promise: nil)

        if let bodyBuffer {
            context.write(wrapOutboundOut(.body(.byteBuffer(bodyBuffer))), promise: nil)
        }

        return context.writeAndFlush(wrapOutboundOut(.end(nil)))
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}

extension HTTPRequestHandler: @unchecked Sendable {}

private final class ServerLifecycleHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart

    func channelActive(context: ChannelHandlerContext) {
        context.fireChannelActive()
    }

    func channelInactive(context: ChannelHandlerContext) {
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}

// MARK: - Request construction

private extension CapturedRequest {
    static func make(from head: HTTPRequestHead, bodyBuffer: inout ByteBuffer) -> CapturedRequest {
        let uri = head.uri
        let components = URLComponents(string: uri) ?? URLComponents()
        let path = components.path.isEmpty ? "/" : components.path

        let query = components.queryItems?.reduce(into: [String: [String]]()) { result, item in
            result[item.name, default: []].append(item.value ?? "")
        } ?? [:]

        let headers = head.headers.map { Header(name: $0.name, value: $0.value) }
        let data = Data(bodyBuffer.readableBytesView)
        bodyBuffer.moveReaderIndex(forwardBy: bodyBuffer.readableBytes)

        return CapturedRequest(
            method: head.method,
            uri: uri,
            path: path,
            queryParameters: query,
            headers: headers,
            body: data
        )
    }
}
