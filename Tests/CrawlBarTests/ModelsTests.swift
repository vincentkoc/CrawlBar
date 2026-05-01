import CrawlBarCore
import XCTest

final class ModelsTests: XCTestCase {
    func testAppIDSortsByRawValue() {
        XCTAssertEqual([CrawlAppID(rawValue: "b"), CrawlAppID(rawValue: "a")].sorted().map(\.rawValue), ["a", "b"])
    }
}
