import Foundation
import HTTPTypes

struct ResponseFormatter {
    private let pretty: PrettyMode

    init(pretty: PrettyMode) {
        self.pretty = pretty
    }

    func format(_ payloads: [ResponsePayload]) -> String {
        guard !payloads.isEmpty else {
            return ""
        }

        var output = ""
        for (index, payload) in payloads.enumerated() {
            if index > 0 {
                output.append("\n")
            }
            output.append(formatSingle(payload))
        }
        return output
    }

    private func formatSingle(_ payload: ResponsePayload) -> String {
        var lines: [String] = []
        lines.append(statusLine(for: payload.response.status))

        for field in payload.response.headerFields {
            lines.append(headerLine(for: field))
        }

        let headerSection = lines.joined(separator: "\n")

        guard let bodySection = bodySection(for: payload.body) else {
            return headerSection + "\n"
        }

        return headerSection + "\n\n" + bodySection + "\n"
    }

    private func reasonPhrase(for status: HTTPResponse.Status) -> String {
        if !status.reasonPhrase.isEmpty {
            return status.reasonPhrase
        }

        let localized = HTTPURLResponse.localizedString(forStatusCode: status.code)
        if localized.isEmpty {
            return ""
        }

        return localized.capitalized
    }

    private func statusLine(for status: HTTPResponse.Status) -> String {
        let base = "HTTP/1.1 \(status.code) \(reasonPhrase(for: status))"
        guard pretty.enablesColors else {
            return base
        }

        return colorize(base, with: statusColorCode(for: status.code))
    }

    private func headerLine(for field: HTTPField) -> String {
        guard pretty.enablesColors else {
            return "\(field.name): \(field.value)"
        }

        let name = colorize(field.name.rawName, with: "35")
        let value = colorize(field.value, with: "37")
        return "\(name): \(value)"
    }

    private func bodySection(for body: ResponseBody) -> String? {
        switch body {
        case .none:
            return nil
        case .text(let text):
            let formatted = formatTextBody(text)
            if pretty.enablesColors {
                return colorize(formatted, with: "37")
            }
            return formatted
        case .data(let data):
            guard !data.isEmpty else {
                return nil
            }
            let description = "<\(data.count) bytes binary data>"
            if pretty.enablesColors {
                return colorize(description, with: "90")
            }
            return description
        }
    }

    private func formatTextBody(_ text: String) -> String {
        guard pretty.enablesFormatting else {
            return text
        }

        guard let formatted = prettyPrintedJSON(from: text) else {
            return text
        }

        return formatted
    }

    private func prettyPrintedJSON(from text: String) -> String? {
        guard let data = text.data(using: .utf8) else {
            return nil
        }

        do {
            let object = try JSONSerialization.jsonObject(with: data)
            guard JSONSerialization.isValidJSONObject(object) else {
                return nil
            }

            let formatted = try JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted]
            )

            return String(data: formatted, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func colorize(_ text: String, with code: String) -> String {
        "\u{001B}[\(code)m\(text)\u{001B}[0m"
    }

    private func statusColorCode(for statusCode: Int) -> String {
        switch statusCode {
        case 100..<200:
            return "36" // cyan for informational
        case 200..<300:
            return "32" // green for success
        case 300..<400:
            return "33" // yellow for redirects
        case 400..<600:
            return "31" // red for client/server errors
        default:
            return "35" // magenta fallback
        }
    }
}
