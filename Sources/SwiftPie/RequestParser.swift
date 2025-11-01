import Foundation

public struct RequestParserOptions: Equatable, Sendable {
    public enum DefaultScheme: String, Equatable, Sendable {
        case http
        case https

        var scheme: String { rawValue }
    }

    public var defaultScheme: DefaultScheme
    public var baseURL: URL?

    public static let `default` = RequestParserOptions()

    public init(defaultScheme: DefaultScheme = .http, baseURL: URL? = nil) {
        self.defaultScheme = defaultScheme
        self.baseURL = baseURL
    }
}

enum RequestParser {
    static func parse(
        arguments: [String],
        options: RequestParserOptions = .default
    ) throws -> ParsedRequest {
        var iterator = arguments[...]

        let explicitMethod: HTTPMethod?
        if let candidate = iterator.first,
           let method = parseMethodToken(candidate) {
            explicitMethod = method
            iterator = iterator.dropFirst()
        } else {
            explicitMethod = nil
        }

        guard let rawURLToken = iterator.first else {
            throw RequestParserError.missingURL
        }
        iterator = iterator.dropFirst()

        let normalizedURLToken = normalizeURLToken(rawURLToken, options: options)
        guard var components = URLComponents(string: normalizedURLToken) else {
            throw RequestParserError.invalidURL(rawURLToken)
        }

        var items = RequestItems()
        var queryFields = queryFields(from: components.queryItems ?? [])
        components.queryItems = nil

        for token in iterator {
            let item = try parseItem(token)
            switch item {
            case .header(let field):
                items.headers.append(field)
            case .data(let field):
                items.data.append(field)
            case .query(name: let name, value: let value):
                appendQueryField(&queryFields, name: name, value: value)
            case .file(let file):
                items.files.append(file)
            }
        }

        if !queryFields.isEmpty {
            components.queryItems = queryFields
                .flatMap { field in
                    field.values.map { URLQueryItem(name: field.name, value: $0) }
                }
        }

        guard let finalURL = components.url else {
            throw RequestParserError.invalidURL(normalizedURLToken)
        }

        items.query = queryFields

        let inferredMethod: HTTPMethod
        if let method = explicitMethod {
            inferredMethod = method
        } else if !items.data.isEmpty || !items.files.isEmpty {
            inferredMethod = .post
        } else {
            inferredMethod = .get
        }

        return ParsedRequest(
            method: inferredMethod,
            url: finalURL,
            items: items
        )
    }
}

private enum ParsedItem {
    case header(HeaderField)
    case data(DataField)
    case query(name: String, value: String)
    case file(FileField)
}

private func parseItem(_ token: String) throws -> ParsedItem {
    if let file = try parseFileItem(token) {
        return .file(file)
    }

    let split = try splitKeyValue(token)

    switch split.separator {
    case .header(let produceEmpty):
        let value: HeaderValue = {
            if produceEmpty {
                return .some("")
            }
            if let rawValue = split.value, !rawValue.isEmpty {
                return .some(unescape(rawValue))
            }
            return .none
        }()
        return .header(
            HeaderField(
                name: unescape(split.key),
                value: value
            )
        )
    case .dataString:
        return .data(
            DataField(
                name: unescape(split.key),
                value: .text(unescape(split.value ?? ""))
            )
        )
    case .dataJSON:
        let raw = split.value ?? ""
        let jsonValue = try parseJSONValue(raw)
        return .data(
            DataField(
                name: unescape(split.key),
                value: .json(jsonValue)
            )
        )
    case .query:
        return .query(
            name: unescape(split.key),
            value: unescape(split.value ?? "")
        )
    }
}

private func parseFileItem(_ token: String) throws -> FileField? {
    guard let separatorIndex = firstUnescapedCharacter("@", in: token) else {
        return nil
    }

    let name = unescape(String(token[..<separatorIndex]))
    let pathPortion = String(token[token.index(after: separatorIndex)...])

    guard !name.isEmpty, !pathPortion.isEmpty else {
        throw RequestParserError.invalidFile(token)
    }

    let expandedPath = unescape(pathPortion)
    return FileField(
        name: name,
        path: URL(fileURLWithPath: expandedPath)
    )
}

private func appendQueryField(
    _ fields: inout [QueryField],
    name: String,
    value: String
) {
    if let index = fields.firstIndex(where: { $0.name == name }) {
        fields[index].values.append(value)
    } else {
        fields.append(QueryField(name: name, values: [value]))
    }
}

private func queryFields(from items: [URLQueryItem]) -> [QueryField] {
    var fields: [QueryField] = []
    for item in items {
        appendQueryField(
            &fields,
            name: item.name,
            value: item.value ?? ""
        )
    }
    return fields
}

private enum Separator {
    case header(producesEmptyValue: Bool)
    case dataString
    case dataJSON
    case query
}

private struct KeyValueSplit {
    var key: String
    var value: String?
    var separator: Separator
}

private func splitKeyValue(_ token: String) throws -> KeyValueSplit {
    if token.hasSuffix(";"),
       let last = token.last,
       last == ";",
       token.count > 1,
       !isEscapedCharacter(at: token.index(before: token.endIndex), in: token) {
        let name = String(token.dropLast())
        return KeyValueSplit(
            key: name,
            value: "",
            separator: .header(producesEmptyValue: true)
        )
    }

    guard let separator = findSeparator(in: token) else {
        throw RequestParserError.invalidItem(token)
    }

    let key = String(token[..<separator.range.lowerBound])
    let valueStart = separator.range.upperBound
    let value = valueStart < token.endIndex ? String(token[valueStart...]) : ""

    switch separator.kind {
    case .header:
        return KeyValueSplit(
            key: key,
            value: value,
            separator: .header(producesEmptyValue: false)
        )
    case .dataString:
        return KeyValueSplit(
            key: key,
            value: value,
            separator: .dataString
        )
    case .dataJSON:
        return KeyValueSplit(
            key: key,
            value: value,
            separator: .dataJSON
        )
    case .query:
        return KeyValueSplit(
            key: key,
            value: value,
            separator: .query
        )
    }
}

private enum SeparatorKind {
    case header
    case dataString
    case dataJSON
    case query
}

private struct SeparatorPosition {
    var kind: SeparatorKind
    var range: Range<String.Index>
}

private func findSeparator(in token: String) -> SeparatorPosition? {
    var index = token.startIndex

    while index < token.endIndex {
        if isEscapedCharacter(at: index, in: token) {
            index = token.index(after: index)
            continue
        }

        let nextIndex = token.index(after: index)

        if nextIndex < token.endIndex {
            let peek = token[nextIndex]
            if token[index] == ":" && peek == "=" {
                return SeparatorPosition(
                    kind: .dataJSON,
                    range: index..<token.index(after: nextIndex)
                )
            }

            if token[index] == "=" && peek == "=" {
                return SeparatorPosition(
                    kind: .query,
                    range: index..<token.index(after: nextIndex)
                )
            }
        }

        if token[index] == ":" {
            return SeparatorPosition(
                kind: .header,
                range: index..<token.index(after: index)
            )
        }

        if token[index] == "=" {
            return SeparatorPosition(
                kind: .dataString,
                range: index..<token.index(after: index)
            )
        }

        index = token.index(after: index)
    }

    return nil
}

private func isEscapedCharacter(at index: String.Index, in token: String) -> Bool {
    guard index > token.startIndex else { return false }

    var escapeCount = 0
    var current = token.index(before: index)

    while true {
        if token[current] == "\\" {
            escapeCount += 1
        } else {
            break
        }

        if current == token.startIndex {
            break
        }
        current = token.index(before: current)
    }

    return escapeCount % 2 == 1
}

private func firstUnescapedCharacter(
    _ character: Character,
    in token: String
) -> String.Index? {
    var index = token.startIndex
    while index < token.endIndex {
        if token[index] == character, !isEscapedCharacter(at: index, in: token) {
            return index
        }
        index = token.index(after: index)
    }
    return nil
}

private func unescape(_ input: String) -> String {
    var result = ""
    result.reserveCapacity(input.count)

    var iterator = input.makeIterator()
    var shouldUnescape = false

    while let character = iterator.next() {
        if shouldUnescape {
            result.append(character)
            shouldUnescape = false
            continue
        }

        if character == "\\" {
            shouldUnescape = true
            continue
        }

        result.append(character)
    }

    if shouldUnescape {
        result.append("\\")
    }

    return result
}

private func parseJSONValue(_ rawValue: String) throws -> JSONValue {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let data = trimmed.data(using: .utf8) else {
        throw RequestParserError.invalidJSON(rawValue)
    }

    let json = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    return try JSONValue(any: json)
}

private func normalizeURLToken(
    _ token: String,
    options: RequestParserOptions
) -> String {
    if let shorthand = expandLocalhostShorthand(
        token,
        options: options
    ) {
        return shorthand
    }

    if token.contains("://") {
        return token
    }

    if token.hasPrefix("/"),
       let baseURL = options.baseURL,
       let resolved = URL(string: token, relativeTo: baseURL) {
        return resolved.absoluteString
    }

    return "\(options.defaultScheme.scheme)://\(token)"
}

private func expandLocalhostShorthand(
    _ token: String,
    options: RequestParserOptions
) -> String? {
    guard let first = token.first, first == ":" else {
        return nil
    }

    let defaultScheme = options.defaultScheme

    let schemePrefix = "\(defaultScheme.scheme)://"

    let indexAfterColon = token.index(after: token.startIndex)
    if indexAfterColon < token.endIndex, token[indexAfterColon] == ":" {
        return "\(schemePrefix)\(token)"
    }

    let remainder = token[indexAfterColon...]
    if remainder.isEmpty {
        return "\(schemePrefix)localhost"
    }

    if remainder.first == "/" {
        return "\(schemePrefix)localhost\(remainder)"
    }

    if let slashIndex = remainder.firstIndex(of: "/") {
        let port = remainder[..<slashIndex]
        let path = remainder[slashIndex...]
        return "\(schemePrefix)localhost:\(port)\(path)"
    }

    return "\(schemePrefix)localhost:\(remainder)"
}

private func parseMethodToken(_ token: String) -> HTTPMethod? {
    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          isValidMethodToken(trimmed) else {
        return nil
    }

    let uppercase = trimmed.uppercased()
    let containsUppercase = trimmed.rangeOfCharacter(
        from: CharacterSet.uppercaseLetters
    ) != nil

    if containsUppercase {
        return HTTPMethod(rawValue: uppercase)
    }

    if commonHTTPMethodSet.contains(uppercase) {
        return HTTPMethod(rawValue: uppercase)
    }

    return nil
}

private func isValidMethodToken(_ token: String) -> Bool {
    for scalar in token.unicodeScalars {
        if !httpTokenCharacterSet.contains(scalar) {
            return false
        }
    }
    return true
}

private let httpTokenCharacterSet: CharacterSet = {
    var characters = CharacterSet()
    characters.formUnion(CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ"))
    characters.formUnion(CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz"))
    characters.formUnion(CharacterSet(charactersIn: "0123456789"))
    characters.formUnion(CharacterSet(charactersIn: "!#$%&'*+-.^_`|~"))
    return characters
}()

private let commonHTTPMethodSet: Set<String> = [
    "GET",
    "POST",
    "PUT",
    "PATCH",
    "DELETE",
    "HEAD",
    "OPTIONS",
    "TRACE",
    "CONNECT"
]

public enum RequestParserError: Error, Equatable {
    case missingURL
    case invalidURL(String)
    case invalidItem(String)
    case invalidFile(String)
    case invalidJSON(String)
}

extension RequestParserError {
    public var cliDescription: String {
        switch self {
        case .missingURL:
            return "missing URL; provide a URL or shorthand"
        case .invalidURL(let token):
            return "invalid URL '\(token)'"
        case .invalidItem(let token):
            return "invalid request item '\(token)'"
        case .invalidFile(let token):
            return "invalid file reference '\(token)'"
        case .invalidJSON(let value):
            return "invalid JSON value '\(value)'"
        }
    }
}

public struct ParsedRequest: Equatable {
    public var method: HTTPMethod
    public var url: URL
    public var items: RequestItems

    public init(method: HTTPMethod, url: URL, items: RequestItems) {
        self.method = method
        self.url = url
        self.items = items
    }
}

public struct RequestItems: Equatable {
    public var headers: [HeaderField]
    public var data: [DataField]
    public var query: [QueryField]
    public var files: [FileField]

    public init(
        headers: [HeaderField] = [],
        data: [DataField] = [],
        query: [QueryField] = [],
        files: [FileField] = []
    ) {
        self.headers = headers
        self.data = data
        self.query = query
        self.files = files
    }
}

public struct HeaderField: Equatable {
    public var name: String
    public var value: HeaderValue

    public init(name: String, value: HeaderValue) {
        self.name = name
        self.value = value
    }
}

public enum HeaderValue: Equatable {
    case some(String)
    case none
}

public struct DataField: Equatable {
    public var name: String
    public var value: DataValue

    public init(name: String, value: DataValue) {
        self.name = name
        self.value = value
    }
}

public enum DataValue: Equatable {
    case text(String)
    case json(JSONValue)
}

public enum JSONValue: Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(any value: Any) throws {
        switch value {
        case let string as String:
            self = .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case is NSNull:
            self = .null
        case let array as [Any]:
            let converted = try array.map { try JSONValue(any: $0) }
            self = .array(converted)
        case let dictionary as [String: Any]:
            var result: [String: JSONValue] = [:]
            for (key, value) in dictionary {
                result[key] = try JSONValue(any: value)
            }
            self = .object(result)
        default:
            throw RequestParserError.invalidJSON(String(describing: value))
        }
    }
}

public struct QueryField: Equatable {
    public var name: String
    public var values: [String]

    public init(name: String, values: [String]) {
        self.name = name
        self.values = values
    }
}

public struct FileField: Equatable {
    public var name: String
    public var path: URL

    public init(name: String, path: URL) {
        self.name = name
        self.path = path
    }
}

public struct HTTPMethod: Equatable, Hashable, Sendable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.uppercased()
    }

    public static let delete = HTTPMethod(rawValue: "DELETE")
    public static let get = HTTPMethod(rawValue: "GET")
    public static let head = HTTPMethod(rawValue: "HEAD")
    public static let patch = HTTPMethod(rawValue: "PATCH")
    public static let post = HTTPMethod(rawValue: "POST")
    public static let put = HTTPMethod(rawValue: "PUT")
    public static let options = HTTPMethod(rawValue: "OPTIONS")
}
