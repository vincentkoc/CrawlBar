import CrawlBarCore
import Foundation

enum CLIOutput {
    static func writeJSON<T: Encodable>(_ value: T) throws {
        let data = try CrawlCoding.makeJSONEncoder().encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    static func writeError(_ message: String) {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    }
}
