import XCTest

/// 冒烟测试：启动 App、建档、记一次、逛一遍所有页面并截图。
final class SmokeTests: XCTestCase {
    private var shotDir: URL?

    override func setUp() {
        continueAfterFailure = false
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty {
            let url = URL(fileURLWithPath: dir)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            shotDir = url
        }
    }

    private func makeApp(seed: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if seed { app.launchArguments.append("-seedDemo") }
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = shotDir {
            try? screenshot.pngRepresentation.write(to: dir.appendingPathComponent(name + ".png"))
        }
    }

    private func tapTab(_ app: XCUIApplication, _ title: String) {
        let inBar = app.tabBars.buttons[title]
        if inBar.waitForExistence(timeout: 3) {
            inBar.tap()
        } else {
            app.buttons[title].firstMatch.tap()
        }
    }

    func testCreateProfileAndEncounter() {
        let app = makeApp(seed: false)
        app.launch()
        shot(app, "a1-empty")

        let add = app.buttons["addGirl"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()

        let name = app.textFields["girlName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("测试")
        shot(app, "a2-edit")
        app.buttons["saveGirl"].tap()

        let row = app.staticTexts["测试"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        shot(app, "a3-list")
        row.tap()

        let log = app.buttons["logEncounter"].firstMatch
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        shot(app, "a4-detail")
        log.tap()

        let save = app.buttons["saveEncounter"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        shot(app, "a5-encounter-edit")
        save.tap()

        XCTAssertTrue(app.staticTexts["约会记录（1）"].waitForExistence(timeout: 5))
        shot(app, "a6-detail-after")

        tapTab(app, "记录")
        sleep(1)
        shot(app, "a7-records")
    }

    func testBrowseDemoData() {
        let app = makeApp(seed: true)
        app.launch()

        let tabs = ["后宫", "记录", "地图", "统计", "设置"]
        for (index, tab) in tabs.enumerated() {
            tapTab(app, tab)
            sleep(tab == "地图" ? 5 : 1)
            shot(app, "b\(index)-tab")
        }

        tapTab(app, "统计")
        app.swipeUp()
        sleep(1)
        shot(app, "b5-stats-more")
        app.swipeUp()
        sleep(1)
        shot(app, "b6-stats-more2")

        tapTab(app, "后宫")
        let mei = app.staticTexts["小美"].firstMatch
        XCTAssertTrue(mei.waitForExistence(timeout: 5))
        mei.tap()
        sleep(1)
        shot(app, "c1-detail")
        app.swipeUp()
        sleep(1)
        shot(app, "c2-detail-more")
        app.swipeUp()
        sleep(1)
        shot(app, "c3-detail-more2")
    }
}
