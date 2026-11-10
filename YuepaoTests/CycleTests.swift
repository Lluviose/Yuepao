import Foundation
import XCTest
@testable import Yuepao

final class CycleTests: XCTestCase {
    func testFirstEditOfLegacyPeriodKeepsTheSelectedEntry() throws {
        var details = try legacyDetails()
        var selected = try XCTUnwrap(details.periodEntries.first)
        selected.end = try date(2026, 10, 17)

        // 和周期编辑页一样，在保存时重新读取档案，再按展示时的 ID 更新。
        var entries = details.periodEntries
        let index = try XCTUnwrap(entries.firstIndex { $0.id == selected.id })
        entries[index] = selected
        details.setPeriods(entries)

        XCTAssertEqual(details.periodEntries.first?.end, selected.end)
        XCTAssertEqual(details.periodEntries.first?.id, selected.id)
        XCTAssertTrue(details.periodStarts.isEmpty)
        let reloaded = JSONCoding.decode(GirlDetails.self, from: JSONCoding.encode(details), fallback: GirlDetails())
        XCTAssertEqual(reloaded.periodEntries, details.periodEntries)
    }

    func testFirstDeleteOfLegacyPeriodRemovesTheSelectedEntry() throws {
        var details = try legacyDetails()
        let selected = try XCTUnwrap(details.periodEntries.first)

        details.setPeriods(details.periodEntries.filter { $0.id != selected.id })

        XCTAssertEqual(details.periodEntries.count, 1)
        XCTAssertEqual(details.periodEntries.first?.start, try date(2026, 11, 10))
        XCTAssertFalse(details.periodEntries.contains { $0.id == selected.id })
        XCTAssertTrue(details.periodStarts.isEmpty)
    }

    func testLegacyPeriodIDsSurviveReloadAndDistinguishDuplicateDates() throws {
        var details = try legacyDetails()
        details.periodStarts.append(try date(2026, 10, 13))
        let ids = details.periodEntries.map(\.id)
        let reloaded = JSONCoding.decode(GirlDetails.self, from: JSONCoding.encode(details), fallback: GirlDetails())

        XCTAssertEqual(ids, details.periodEntries.map(\.id))
        XCTAssertEqual(ids, reloaded.periodEntries.map(\.id))
        XCTAssertEqual(Set(ids).count, 3)
    }

    func testNextStartBeforeOnAndAfterPredictedDay() throws {
        let info = CycleInfo(entries: [PeriodEntry(start: try date(2026, 10, 13))], defaultLength: 5)
        let predictedDay = try day(2026, 11, 10)

        XCTAssertEqual(info.nextStart(on: try date(2026, 11, 9)), predictedDay)
        XCTAssertEqual(info.nextStart(on: try date(2026, 11, 10)), predictedDay)
        XCTAssertEqual(info.nextStart(on: try date(2026, 11, 11)), try day(2026, 12, 8))
    }

    private func legacyDetails() throws -> GirlDetails {
        // 旧版 JSON 只有 periodStarts，其余字段由兼容解码补齐。
        let dates = [try date(2026, 10, 13), try date(2026, 11, 10)]
        let data = try JSONSerialization.data(withJSONObject: ["periodStarts": dates.map(\.timeIntervalSinceReferenceDate)])
        return JSONCoding.decode(GirlDetails.self, from: data, fallback: GirlDetails())
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        Calendar.current.startOfDay(for: try date(year, month, day))
    }
}
