import Foundation
import HTTPTypes

struct EncodedBody {
    var data: Data
    var contentType: String?
}

enum RequestPayloadEncoding {
    static func encodeBody(from payload: RequestPayload) throws -> EncodedBody? {
        if payload.data.isEmpty, payload.files.isEmpty {
            return nil
        }

        if !payload.files.isEmpty {
            return try encodeMultipartBody(from: payload)
        }

        if payload.data.contains(where: { field in
            if case .json = field.value {
                return true
            }
            return false
        }) {
            return try encodeJSONBody(from: payload.data)
        }

        return encodeFormBody(from: payload.data)
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
            case .json(let json):
                valueString = try json.asJSONString()
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
            case .json(let json):
                value = try json.toJSONObject()
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

    private static func encodeFormBody(from fields: [DataField]) -> EncodedBody {
        let components = fields.map { field -> String in
            let encodedName = field.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? field.name
            let encodedValue: String
            switch field.value {
            case .text(let string):
                encodedValue = string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? string
            case .json(let json):
                let jsonString = (try? json.asJSONString()) ?? ""
                encodedValue = jsonString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? jsonString
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
