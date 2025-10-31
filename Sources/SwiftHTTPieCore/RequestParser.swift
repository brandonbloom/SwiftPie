import Foundation

enum RequestParser {
    static func parse(arguments: [String]) throws -> ParsedRequest {
        var iterator = arguments[...]

        let explicitMethod: HTTPMethod?
        if let candidate = iterator.first,
           let method = HTTPMethod(rawValue: candidate.uppercased()) {
            explicitMethod = method
            iterator = iterator.dropFirst()
        } else {
            explicitMethod = nil
        }

        guard let rawURLToken = iterator.first else {
            throw RequestParserError.missingURL
        }
        iterator = iterator.dropFirst()

        let normalizedURLToken = normalizeURLToken(rawURLToken)
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

private func normalizeURLToken(_ token: String) -> String {
    if let shorthand = expandLocalhostShorthand(token) {
        return shorthand
    }

    if token.contains("://") {
        return token
    }

    return "http://\(token)"
}

private func expandLocalhostShorthand(_ token: String) -> String? {
    guard let first = token.first, first == ":" else {
        return nil
    }

    let indexAfterColon = token.index(after: token.startIndex)
    if indexAfterColon < token.endIndex, token[indexAfterColon] == ":" {
        return "http://\(token)"
    }

    let remainder = token[indexAfterColon...]
    if remainder.isEmpty {
        return "http://localhost"
    }

    if remainder.first == "/" {
        return "http://localhost\(remainder)"
    }

    if let slashIndex = remainder.firstIndex(of: "/") {
        let port = remainder[..<slashIndex]
        let path = remainder[slashIndex...]
        return "http://localhost:\(port)\(path)"
    }

    return "http://localhost:\(remainder)"
}

enum RequestParserError: Error, Equatable {
    case missingURL
    case invalidURL(String)
    case invalidItem(String)
    case invalidFile(String)
    case invalidJSON(String)
}

struct ParsedRequest: Equatable {
    var method: HTTPMethod
    var url: URL
    var items: RequestItems
}

struct RequestItems: Equatable {
    var headers: [HeaderField] = []
    var data: [DataField] = []
    var query: [QueryField] = []
    var files: [FileField] = []
}

struct HeaderField: Equatable {
    var name: String
    var value: HeaderValue
}

enum HeaderValue: Equatable {
    case some(String)
    case none
}

struct DataField: Equatable {
    var name: String
    var value: DataValue
}

enum DataValue: Equatable {
    case text(String)
    case json(JSONValue)
}

enum JSONValue: Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(any value: Any) throws {
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

struct QueryField: Equatable {
    var name: String
    var values: [String]
}

struct FileField: Equatable {
    var name: String
    var path: URL
}

enum HTTPMethod: String, Equatable, CaseIterable {
    case delete = "DELETE"
    case get = "GET"
    case head = "HEAD"
    case patch = "PATCH"
    case post = "POST"
    case put = "PUT"
    case options = "OPTIONS"
}
