import Foundation
import NIO
import NIOConcurrencyHelpers
import NIOHTTP1
import NIOPosix

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

    public var method: HTTPMethod
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
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(HTTPRequestHandler(router: router))
                }
            }

        let channel = try bootstrap.bind(host: configuration.host, port: configuration.port ?? 0).wait()
        guard let localAddress = channel.localAddress, let port = localAddress.port else {
            throw TestServerError.unableToDetermineLocalAddress
        }

        let baseURL = URL(string: "http://\(configuration.host):\(port)")!

        return NIOHTTPTestServer(
            baseURL: baseURL,
            configuration: configuration,
            recorder: recorder,
            group: group,
            channel: channel,
            router: router
        )
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

struct TestServerRouter: @unchecked Sendable {
    private let recorder: RequestRecorder
    private let allocator = ByteBufferAllocator()

    init(recorder: RequestRecorder) {
        self.recorder = recorder
    }

    func handle(
        request: CapturedRequest,
        head: HTTPRequestHead
    ) -> TestServerResponse {
        recorder.record(request)

        switch (head.method, request.path) {
        case (_, "/get"):
            return makeGetResponse(for: request)

        case (_, "/post"):
            return makePostResponse(for: request)

        case (_, "/headers"):
            return makeHeadersResponse(for: request)

        case (_, _):
            if request.path.hasPrefix("/status/"),
               let response = makeStatusResponse(for: request) {
                return response
            }

            if request.path == "/redirect-to",
               let response = makeRedirectToResponse(for: request) {
                return response
            }

            if request.path.hasPrefix("/redirect/"),
               let response = makeRedirectLoopResponse(for: request) {
                return response
            }

            if request.path == "/cookies" {
                return makeCookiesResponse(for: request)
            }

            if request.path == "/cookies/set" {
                return makeSetCookiesResponse(for: request)
            }

            return TestServerResponse.json(
                ["error": "not_found", "path": request.path],
                status: .notFound,
                allocator: allocator
            )
        }
    }

    private func makeGetResponse(for request: CapturedRequest) -> TestServerResponse {
        TestServerResponse.json(
            [
                "args": request.singleValueQuery,
                "headers": request.headerDictionary,
                "url": request.fullURL(baseURL: nil),
            ],
            allocator: allocator
        )
    }

    private func makePostResponse(for request: CapturedRequest) -> TestServerResponse {
        let contentType = request.headerValues(for: "Content-Type").first?.lowercased() ?? ""
        let rawBody = String(data: request.body, encoding: .utf8) ?? ""

        var jsonPayload: Any?
        var formPayload: [String: String] = [:]

        if contentType.contains("application/json") {
            jsonPayload = try? JSONSerialization.jsonObject(with: request.body, options: [])
        } else if contentType.contains("application/x-www-form-urlencoded") {
            formPayload = request.formPayload
        }

        var object: [String: Any] = [
            "args": request.singleValueQuery,
            "headers": request.headerDictionary,
            "data": rawBody,
        ]

        if let jsonPayload {
            object["json"] = jsonPayload
        } else {
            object["json"] = NSNull()
        }

        if !formPayload.isEmpty {
            object["form"] = formPayload
        }

        return TestServerResponse.json(object, allocator: allocator)
    }

    private func makeHeadersResponse(for request: CapturedRequest) -> TestServerResponse {
        TestServerResponse.json(request.headerDictionary, allocator: allocator)
    }

    private func makeStatusResponse(for request: CapturedRequest) -> TestServerResponse? {
        let components = request.path.split(separator: "/")
        guard let last = components.last, let code = Int(last) else {
            return nil
        }

        let status = HTTPResponseStatus(statusCode: code)
        let bodyText = request.queryParameters["body"]?.last ?? status.reasonPhrase

        return TestServerResponse.text(bodyText, status: status, allocator: allocator)
    }

    private func makeRedirectToResponse(for request: CapturedRequest) -> TestServerResponse? {
        guard let target = request.queryParameters["url"]?.last,
              let location = URL(string: target) else {
            return nil
        }

        return TestServerResponse.redirect(to: location.absoluteString, allocator: allocator)
    }

    private func makeRedirectLoopResponse(for request: CapturedRequest) -> TestServerResponse? {
        let components = request.path.split(separator: "/")
        guard components.count == 3, let iterations = Int(components[2]), iterations > 0 else {
            return nil
        }

        if iterations == 1 {
            let location = request.queryParameters["to"]?.last ?? "/get"
            return TestServerResponse.redirect(to: location, allocator: allocator)
        } else {
            let next = "/redirect/\(iterations - 1)"
            return TestServerResponse.redirect(to: next, allocator: allocator)
        }
    }

    private func makeCookiesResponse(for request: CapturedRequest) -> TestServerResponse {
        let cookies = request.cookies
        return TestServerResponse.json(["cookies": cookies], allocator: allocator)
    }

    private func makeSetCookiesResponse(for request: CapturedRequest) -> TestServerResponse {
        var headers = HTTPHeaders()

        for (name, values) in request.queryParameters {
            for value in values {
                headers.add(name: "Set-Cookie", value: "\(name)=\(value)")
            }
        }

        return TestServerResponse(
            status: .ok,
            headers: headers,
            body: .empty
        )
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

    static func json(
        _ object: Any,
        status: HTTPResponseStatus = .ok,
        allocator: ByteBufferAllocator
    ) -> TestServerResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        return TestServerResponse.data(data, status: status, headers: headers, allocator: allocator)
    }

    static func text(
        _ string: String,
        status: HTTPResponseStatus = .ok,
        allocator: ByteBufferAllocator
    ) -> TestServerResponse {
        let data = string.data(using: .utf8) ?? Data()
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
        return TestServerResponse.data(data, status: status, headers: headers, allocator: allocator)
    }

    static func data(
        _ data: Data,
        status: HTTPResponseStatus = .ok,
        headers: HTTPHeaders? = nil,
        allocator: ByteBufferAllocator
    ) -> TestServerResponse {
        let responseHeaders = headers ?? HTTPHeaders()
        var buffer = allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)

        return TestServerResponse(
            status: status,
            headers: responseHeaders,
            body: .buffer(buffer)
        )
    }

    static func redirect(to location: String, allocator: ByteBufferAllocator) -> TestServerResponse {
        var headers = HTTPHeaders()
        headers.add(name: "Location", value: location)
        return TestServerResponse(status: .found, headers: headers, body: .empty)
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
}

extension HTTPRequestHandler: @unchecked Sendable {}

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
