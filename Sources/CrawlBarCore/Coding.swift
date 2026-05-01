import Foundation

public enum CrawlCoding {
    public static func makeJSONEncoder(pretty: Bool = true) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if pretty {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        return encoder
    }

    public static func makeJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                if let date = ISO8601DateFormatter.crawlBarFormatter().date(from: string) {
                    return date
                }
                if let seconds = Double(string) {
                    return Date(timeIntervalSince1970: seconds)
                }
            }
            if let milliseconds = try? container.decode(Int64.self), milliseconds > 10_000_000_000 {
                return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
            }
            let seconds = try container.decode(Double.self)
            return Date(timeIntervalSince1970: seconds)
        }
        return decoder
    }
}

extension ISO8601DateFormatter {
    static func crawlBarFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

public extension String {
    var nilIfBlank: String? {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
