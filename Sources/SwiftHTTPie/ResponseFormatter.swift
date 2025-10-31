import Foundation
import HTTPTypes

struct ResponseFormatter {
    func format(_ payload: ResponsePayload) -> String {
        var lines: [String] = []
        let status = payload.response.status
        lines.append("HTTP/1.1 \(status.code) \(status.reasonPhrase)")

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
}
