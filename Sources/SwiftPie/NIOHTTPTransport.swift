#if canImport(CoreFoundation)
import CoreFoundation
#endif
import Foundation
import HTTPTypes
@preconcurrency import NIO
@preconcurrency import NIOCore
@preconcurrency import NIOHTTP1
@preconcurrency import NIOPosix
@preconcurrency import NIOSSL

public final class NIOHTTPTransport: RequestTransport, @unchecked Sendable {
    private static let sharedGroup: EventLoopGroup = {
        MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }()

    private let group: EventLoopGroup
    private let ownsGroup: Bool

    public init(eventLoopGroup: EventLoopGroup? = nil) {
        if let eventLoopGroup {
            self.group = eventLoopGroup
            self.ownsGroup = false
        } else {
            self.group = NIOHTTPTransport.sharedGroup
            self.ownsGroup = false
        }
    }

    deinit {
        if ownsGroup {
            let group = self.group
            group.shutdownGracefully { _ in }
        }
    }

    public func send(_ payload: RequestPayload, options: TransportOptions) throws -> ResponsePayload {
        let components = try makeRequestComponents(from: payload, options: options)
        let timeoutMilliseconds = options.timeout.map { Int64(($0 * 1000).rounded(.up)) }
        let timeoutAmount = timeoutMilliseconds.map { TimeAmount.milliseconds($0) }

        let collector = ResponseCollector(timeout: timeoutAmount, timeoutMilliseconds: timeoutMilliseconds)

        var bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                var steps: [EventLoopFuture<Void>] = []

                if components.isTLS {
                    steps.append(self.configureTLS(
                        on: channel,
                        host: components.tlsHostname,
                        verification: options.verify
                    ))
                }

                steps.append(channel.pipeline.addHTTPClientHandlers())
                steps.append(channel.pipeline.addHandler(collector))

                return EventLoopFuture.andAllSucceed(steps, on: channel.eventLoop)
            }

        if let timeoutAmount {
            bootstrap = bootstrap.connectTimeout(timeoutAmount)
        }

        let channel: Channel
        do {
            channel = try bootstrap.connect(host: components.connectHost, port: components.port).wait()
        } catch {
            throw mapError(error)
        }

        defer {
            channel.close(mode: .all, promise: nil)
        }

        do {
            try sendRequest(components, on: channel)
        } catch {
            throw mapError(error)
        }

        do {
            let result = try collector.future.wait()
            return makeResponse(from: result)
        } catch {
            throw mapError(error)
        }
    }
}

// MARK: - Request construction

private struct RequestComponents {
    var method: NIOHTTP1.HTTPMethod
    var uri: String
    var headers: HTTPHeaders
    var body: Data?
    var isTLS: Bool
    var connectHost: String
    var tlsHostname: String?
    var port: Int
}

private extension NIOHTTPTransport {
    func makeRequestComponents(
        from payload: RequestPayload,
        options: TransportOptions
    ) throws -> RequestComponents {
        guard
            let scheme = payload.request.scheme,
            let authority = payload.request.authority
        else {
            throw TransportError.internalFailure("missing scheme or authority in request payload")
        }

        let path = payload.request.path ?? "/"
        guard let url = URL(string: "\(scheme)://\(authority)\(path)") else {
            throw TransportError.internalFailure("unable to build URL for request '\(scheme)://\(authority)\(path)'")
        }

        guard let host = url.host else {
            throw TransportError.internalFailure("missing host for request '\(url.absoluteString)'")
        }

        let isTLS = (scheme.lowercased() == "https")
        let defaultPort = isTLS ? 443 : 80
        let port = url.port ?? defaultPort
        let connectHost = host
        let tlsHostname: String? = isTLS ? host : nil

        let uri = path

        var headers = HTTPHeaders()
        for field in payload.request.headerFields {
            headers.add(name: field.name.rawName, value: field.value)
        }

        if let hostField = HTTPField.Name("Host"),
           !payload.headerRemovals.contains(hostField),
           !headers.contains(name: "Host") {
            headers.add(name: "Host", value: hostHeaderValue(from: url, defaultPort: defaultPort))
        }

        if options.httpVersionPreference == .http1Only,
           let connectionField = HTTPField.Name("Connection"),
           RequestPayloadEncoding.shouldApplyDefaultHeader(named: connectionField, for: payload),
           !headers.contains(name: "Connection") {
            headers.add(name: "Connection", value: "close")
        }

        let encodedBody = try RequestPayloadEncoding.encodeBody(from: payload)

        if let encodedBody {
            if let contentType = encodedBody.contentType,
               let contentTypeName = HTTPField.Name("Content-Type"),
               RequestPayloadEncoding.shouldApplyDefaultHeader(named: contentTypeName, for: payload),
               !headers.contains(name: "Content-Type")
            {
                headers.add(name: "Content-Type", value: contentType)
            }

            if !headers.contains(name: "Content-Length") {
                headers.add(name: "Content-Length", value: "\(encodedBody.data.count)")
            }
        } else if payload.bodyMode == .raw,
                  let contentTypeName = HTTPField.Name("Content-Type"),
                  RequestPayloadEncoding.shouldApplyDefaultHeader(named: contentTypeName, for: payload) {
            headers.remove(name: "Content-Type")
        }

        let body = encodedBody?.data

        return RequestComponents(
            method: NIOHTTP1.HTTPMethod(rawValue: payload.request.method.rawValue),
            uri: uri,
            headers: headers,
            body: body,
            isTLS: isTLS,
            connectHost: connectHost,
            tlsHostname: tlsHostname,
            port: port
        )
    }

    func sendRequest(_ components: RequestComponents, on channel: Channel) throws {
        var head = HTTPRequestHead(
            version: .http1_1,
            method: components.method,
            uri: components.uri
        )
        head.headers = components.headers

        channel.write(HTTPClientRequestPart.head(head), promise: nil)

        if let body = components.body, !body.isEmpty {
            var buffer = channel.allocator.buffer(capacity: body.count)
            buffer.writeBytes(body)
            channel.write(HTTPClientRequestPart.body(.byteBuffer(buffer)), promise: nil)
        }

        try channel.writeAndFlush(HTTPClientRequestPart.end(nil)).wait()
    }
}

// MARK: - Response handling

private struct ResponseResult {
    var head: HTTPResponseHead
    var body: ByteBuffer
}

private extension NIOHTTPTransport {
    func makeResponse(from result: ResponseResult) -> ResponsePayload {
        var fields = HTTPFields()
        for (name, value) in result.head.headers {
            guard let headerName = HTTPField.Name(name) else {
                continue
            }
            fields.append(HTTPField(name: headerName, value: value))
        }

        let status = HTTPResponse.Status(
            code: Int(result.head.status.code),
            reasonPhrase: result.head.status.reasonPhrase
        )
        let response = HTTPResponse(status: status, headerFields: fields)

        let body = makeResponseBody(buffer: result.body, headers: result.head.headers)
        return ResponsePayload(response: response, body: body)
    }

    func makeResponseBody(buffer: ByteBuffer, headers: HTTPHeaders) -> ResponseBody {
        let content = buffer
        guard content.readableBytes > 0 else {
            return .none
        }

        let data = Data(content.readableBytesView)
        if let text = decodeTextBody(data: data, headers: headers) {
            return .text(text)
        }

        return .data(data)
    }

    func decodeTextBody(data: Data, headers: HTTPHeaders) -> String? {
        let contentType = headers.first(name: "Content-Type")

        if let encoding = charsetEncoding(from: contentType) {
            if let decoded = String(data: data, encoding: encoding) {
                return decoded
            }
        }

        if isTextual(mimeType: contentType) {
            if let utf8 = String(data: data, encoding: .utf8) {
                return utf8
            }

            if let latin1 = String(data: data, encoding: .isoLatin1) {
                return latin1
            }
        }

        return nil
    }
}

// MARK: - Helpers

private extension NIOHTTPTransport {
    func configureTLS(
        on channel: Channel,
        host: String?,
        verification: TransportOptions.TLSVerification
    ) -> EventLoopFuture<Void> {
        do {
            var configuration = TLSConfiguration.makeClientConfiguration()
            if verification == .disabled {
                configuration.certificateVerification = .none
            }
            let context = try NIOSSLContext(configuration: configuration)
            let handler = try NIOSSLClientHandler(context: context, serverHostname: host)
            return channel.pipeline.addHandler(handler)
        } catch {
            return channel.eventLoop.makeFailedFuture(error)
        }
    }

    func hostHeaderValue(from url: URL, defaultPort: Int) -> String {
        guard let host = url.host else {
            return ""
        }

        let formattedHost: String
        if host.contains(":"), !host.hasPrefix("["), !host.hasSuffix("]") {
            formattedHost = "[\(host)]"
        } else {
            formattedHost = host
        }

        if let port = url.port, port != defaultPort {
            return "\(formattedHost):\(port)"
        }

        return formattedHost
    }

    func charsetEncoding(from contentType: String?) -> String.Encoding? {
        guard let contentType else { return nil }

        let parameters = contentType
            .split(separator: ";")
            .dropFirst()

        for parameter in parameters {
            let parts = parameter.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if name != "charset" {
                continue
            }

            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            return encoding(for: value)
        }

        return nil
    }

    func encoding(for charset: String) -> String.Encoding? {
#if canImport(CoreFoundation) && !os(Linux)
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else {
            return nil
        }

        let rawValue = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: rawValue)
#else
        switch charset.lowercased() {
        case "utf-8", "utf8":
            return .utf8
        case "iso-8859-1", "latin1", "latin-1":
            return .isoLatin1
        default:
            return nil
        }
#endif
    }

    func isTextual(mimeType: String?) -> Bool {
        guard let mimeType else { return true }
        let lowercased = mimeType.lowercased()

        if lowercased.hasPrefix("text/") {
            return true
        }

        if lowercased == "application/json" ||
            lowercased.hasSuffix("+json") ||
            lowercased == "application/xml" ||
            lowercased.hasSuffix("+xml") ||
            lowercased == "application/x-www-form-urlencoded" {
            return true
        }

        return false
    }

    func mapError(_ error: Error) -> TransportError {
        if let transportError = error as? TransportError {
            return transportError
        }

        if let sslError = error as? NIOSSLError {
            return .networkError(sslError.localizedDescription)
        }

        if let connectionError = error as? NIOConnectionError {
            return .networkError(connectionError.localizedDescription)
        }

        if let channelError = error as? ChannelError {
            return .networkError(channelError.localizedDescription)
        }

        return .internalFailure(error.localizedDescription)
    }
}

// MARK: - Response collector

private final class ResponseCollector: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPClientResponsePart

    private let timeout: TimeAmount?
    private let timeoutMilliseconds: Int64?
    private var timeoutTask: Scheduled<Void>?
    private var head: HTTPResponseHead?
    private var buffer: ByteBuffer?
    private var promise: EventLoopPromise<ResponseResult>?
    private weak var channel: Channel?
    private var completed = false

    init(timeout: TimeAmount?, timeoutMilliseconds: Int64?) {
        self.timeout = timeout
        self.timeoutMilliseconds = timeoutMilliseconds
    }

    var future: EventLoopFuture<ResponseResult> {
        guard let promise else {
            fatalError("ResponseCollector must be added to a channel pipeline before use.")
        }
        return promise.futureResult
    }

    func handlerAdded(context: ChannelHandlerContext) {
        promise = context.eventLoop.makePromise(of: ResponseResult.self)
        channel = context.channel

        if let timeout {
            timeoutTask = context.eventLoop.scheduleTask(in: timeout) { [weak self] in
                guard let self else { return }
                let message: String
                if let milliseconds = self.timeoutMilliseconds {
                    if milliseconds >= 1000 {
                        let seconds = Int((Double(milliseconds) / 1000.0).rounded(.up))
                        message = "request timed out after \(seconds)s"
                    } else {
                        message = "request timed out after ~\(milliseconds)ms"
                    }
                } else {
                    message = "request timed out"
                }
                self.promise?.fail(TransportError.networkError(message))
                self.completed = true
                self.channel?.close(promise: nil)
            }
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {
        case .head(let head):
            self.head = head
        case .body(var chunk):
            if var existing = buffer {
                existing.writeBuffer(&chunk)
                buffer = existing
            } else {
                buffer = chunk
            }
        case .end:
            timeoutTask?.cancel()
            guard let head else {
                promise?.fail(TransportError.internalFailure("missing HTTP response head"))
                completed = true
                return
            }
            let body = buffer ?? context.channel.allocator.buffer(capacity: 0)
            promise?.succeed(ResponseResult(head: head, body: body))
            completed = true
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        timeoutTask?.cancel()
        guard let promise, !completed else {
            return
        }

        if let head {
            let body = buffer ?? context.channel.allocator.buffer(capacity: 0)
            promise.succeed(ResponseResult(head: head, body: body))
            completed = true
        } else {
            promise.fail(TransportError.networkError("connection closed before response was received"))
            completed = true
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        timeoutTask?.cancel()
        if let promise, !completed {
            promise.fail(error)
            completed = true
        }
        context.close(promise: nil)
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        timeoutTask?.cancel()
        if let promise, !completed {
            promise.fail(TransportError.networkError("connection closed before response was received"))
            completed = true
        }
    }
}
