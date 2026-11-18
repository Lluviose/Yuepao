import XCTest
@testable import Yuepao

final class JournalOptionsTests: XCTestCase {
    func testEveryDefaultIsReachableInOneCycle() {
        for key: OptionKey in [.personality, .activities, .moods] {
            let groups = JournalOptions.catalog(for: key, configured: key.defaults, selected: [])
            let words = JournalOptions.suggestions(from: groups)
            XCTAssertEqual(Set(words), Set(key.defaults))
            XCTAssertEqual(words.count, key.defaults.count)
            XCTAssertEqual(Array(words.prefix(groups.count)), groups.compactMap { $0.words.first })
        }
    }

    func testCustomizedLibraryAndHistoricalSelections() {
        let groups = JournalOptions.catalog(for: .activities, configured: ["野餐", "散步", "画画"],
                                            selected: ["散步", "老地方", "老地方"])
        XCTAssertEqual(groups.map(\.words), [["野餐", "散步"], ["画画", "老地方"]])
        XCTAssertTrue(JournalOptions.catalog(for: .moods, configured: [], selected: []).isEmpty)
    }
}
