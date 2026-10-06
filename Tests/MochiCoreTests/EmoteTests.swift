import XCTest
@testable import MochiCore

final class EmoteTests: XCTestCase {
    func testCatalogContainsStandardEmotes() {
        let all = EmoteCatalog.all
        XCTAssertGreaterThanOrEqual(all.count, 20)
        XCTAssertTrue(all.contains { $0.id == "this_is_fine" })
        XCTAssertTrue(all.contains { $0.id == "table_flip" })
        XCTAssertTrue(all.contains { $0.id == "coffee" })
        XCTAssertTrue(all.contains { $0.id == "dance" })
    }

    func testSearchFiltersByQueryCaseInsensitive() {
        let results = EmoteCatalog.search(query: "TABLE", category: .all)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, "table_flip")
    }

    func testSearchFiltersByCategory() {
        let workEmotes = EmoteCatalog.search(query: "", category: .work)
        XCTAssertFalse(workEmotes.isEmpty)
        XCTAssertTrue(workEmotes.allSatisfy { $0.category == .work })
        XCTAssertFalse(workEmotes.contains { $0.id == "dance" })
    }

    func testEmptyQueryReturnsAllForCategory() {
        let all = EmoteCatalog.search(query: "", category: .all)
        XCTAssertEqual(all.count, EmoteCatalog.all.count)
    }
}
