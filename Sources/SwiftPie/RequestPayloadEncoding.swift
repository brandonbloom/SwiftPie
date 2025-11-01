import Foundation
import HTTPTypes

struct EncodedBody {
    var data: Data
    var contentType: String?
}

enum RequestPayloadEncoding {
    static func encodeBody(from payload: RequestPayload) throws -> EncodedBody? {
        switch payload.bodyMode {
        case .raw:
            guard let rawBody = payload.rawBody else {
                return nil
            }

            let data: Data
            switch rawBody {
            case .inline(let string):
                data = string.data(using: .utf8) ?? Data(string.utf8)
            case .data(let rawData):
                data = rawData
            }

            return EncodedBody(data: data, contentType: nil)
        case .json:
            if payload.data.isEmpty, payload.files.isEmpty {
                return nil
            }

            if !payload.files.isEmpty {
                return try encodeMultipartBody(from: payload)
            }

            return try encodeJSONBody(from: payload.data)
        case .form:
            if payload.data.isEmpty, payload.files.isEmpty {
                return nil
            }

            if !payload.files.isEmpty {
                return try encodeMultipartBody(from: payload)
            }

            return try encodeFormBody(from: payload.data)
        }
    }

    static func shouldApplyDefaultHeader(
        named name: HTTPField.Name,
        for payload: RequestPayload
    ) -> Bool {
        if payload.headerRemovals.contains(name) {
            return false
        }

        for field in payload.request.headerFields where field.name == name {
            return false
        }

        return true
    }

    private static func encodeMultipartBody(from payload: RequestPayload) throws -> EncodedBody {
        let boundary = "boundary-\(UUID().uuidString)"
        var body = Data()

        func append(_ string: String) {
            guard let data = string.data(using: .utf8) else { return }
            body.append(data)
        }

        for dataField in payload.data {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(escapeMultipartFieldName(dataField.name))\"\r\n")
            append("\r\n")

            let valueString: String
            switch dataField.value {
            case .text(let text):
                valueString = text
            case .textFile(let url):
                do {
                    valueString = try String(contentsOf: url, encoding: .utf8)
                } catch {
                    throw TransportError.internalFailure("failed to read data file '\(url.path)': \(error.localizedDescription)")
                }
            case .json(let json):
                valueString = try json.asJSONString()
            case .jsonFile(let url):
                do {
                    let contents = try Data(contentsOf: url)
                    let json = try JSONValue.parse(from: contents)
                    valueString = try json.asJSONString()
                } catch let error as TransportError {
                    throw error
                } catch {
                    throw TransportError.internalFailure("failed to read JSON data file '\(url.path)': \(error.localizedDescription)")
                }
            case .textStdin, .jsonStdin:
                throw TransportError.internalFailure("stdin data should be resolved before encoding")
            }

            append("\(valueString)\r\n")
        }

        for fileField in payload.files {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(escapeMultipartFieldName(fileField.name))\"; filename=\"\(fileField.path.lastPathComponent)\"\r\n")
            append("Content-Type: application/octet-stream\r\n")
            append("\r\n")

            let fileData: Data
            do {
                fileData = try Data(contentsOf: fileField.path)
            } catch {
                throw TransportError.internalFailure("failed to read file '\(fileField.path.path)': \(error.localizedDescription)")
            }

            body.append(fileData)
            append("\r\n")
        }

        append("--\(boundary)--\r\n")

        return EncodedBody(
            data: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
    }

    private static func encodeJSONBody(from fields: [DataField]) throws -> EncodedBody {
        var object: [String: Any] = [:]

        for field in fields {
            let value: Any
            switch field.value {
            case .text(let string):
                value = string
            case .textFile(let url):
                do {
                    value = try String(contentsOf: url, encoding: .utf8)
                } catch {
                    throw TransportError.internalFailure("failed to read data file '\(url.path)': \(error.localizedDescription)")
                }
            case .json(let json):
                value = try json.toJSONObject()
            case .jsonFile(let url):
                do {
                    let contents = try Data(contentsOf: url)
                    let json = try JSONValue.parse(from: contents)
                    value = try json.toJSONObject()
                } catch let error as TransportError {
                    throw error
                } catch {
                    throw TransportError.internalFailure("failed to read JSON data file '\(url.path)': \(error.localizedDescription)")
                }
            case .textStdin, .jsonStdin:
                throw TransportError.internalFailure("stdin data should be resolved before encoding")
            }

            if let existing = object[field.name] {
                if var array = existing as? [Any] {
                    array.append(value)
                    object[field.name] = array
                } else {
                    object[field.name] = [existing, value]
                }
            } else {
                object[field.name] = value
            }
        }

        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return EncodedBody(data: data, contentType: "application/json")
    }

    private static func encodeFormBody(from fields: [DataField]) throws -> EncodedBody {
        let components = try fields.map { field -> String in
            let encodedName = field.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? field.name
            let encodedValue: String
            switch field.value {
            case .text(let string):
                encodedValue = string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? string
            case .textFile(let url):
                let string: String
                do {
                    string = try String(contentsOf: url, encoding: .utf8)
                } catch {
                    throw TransportError.internalFailure("failed to read data file '\(url.path)': \(error.localizedDescription)")
                }
                encodedValue = string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? string
            case .json(let json):
                let jsonString = (try? json.asJSONString()) ?? ""
                encodedValue = jsonString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? jsonString
            case .jsonFile(let url):
                let jsonString: String
                do {
                    let contents = try Data(contentsOf: url)
                    let json = try JSONValue.parse(from: contents)
                    jsonString = try json.asJSONString()
                } catch let error as TransportError {
                    throw error
                } catch {
                    throw TransportError.internalFailure("failed to read JSON data file '\(url.path)': \(error.localizedDescription)")
                }
                encodedValue = jsonString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? jsonString
            case .textStdin, .jsonStdin:
                throw TransportError.internalFailure("stdin data should be resolved before encoding")
            }
            return "\(encodedName)=\(encodedValue)"
        }

        let formString = components.joined(separator: "&")
        let data = formString.data(using: .utf8) ?? Data()
        return EncodedBody(
            data: data,
            contentType: "application/x-www-form-urlencoded; charset=utf-8"
        )
    }

    private static func escapeMultipartFieldName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "\"", with: "%22")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }
}

extension JSONValue {
    func toJSONObject() throws -> Any {
        switch self {
        case .string(let string):
            return string
        case .number(let number):
            return number
        case .bool(let value):
            return value
        case .null:
            return NSNull()
        case .array(let values):
            return try values.map { try $0.toJSONObject() }
        case .object(let dictionary):
            var result: [String: Any] = [:]
            for (key, value) in dictionary {
                result[key] = try value.toJSONObject()
            }
            return result
        }
    }

    func asJSONString() throws -> String {
        let object = try toJSONObject()
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? ""
    }
}
