import Foundation
import HTTPTypes

struct ResponseFormatter {
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
        let status = payload.response.status
        lines.append("HTTP/1.1 \(status.code) \(reasonPhrase(for: status))")

        for field in payload.response.headerFields {
            lines.append("\(field.name): \(field.value)")
        }

        let headerSection = lines.joined(separator: "\n")

        switch payload.body {
        case .none:
            return headerSection + "\n"
        case .text(let text):
            return headerSection + "\n\n" + text + "\n"
        case .data(let data):
            guard !data.isEmpty else {
                return headerSection + "\n"
            }

            let description = "<\(data.count) bytes binary data>"
            return headerSection + "\n\n" + description + "\n"
        }
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
}
