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

        XCTAssertTrue(save.waitForNonExistence(timeout: 5))
        sleep(1)
        shot(app, "a6-detail-after")

        // 记录页里应该出现这条记录
        tapTab(app, "记录")
        XCTAssertTrue(app.staticTexts["测试"].firstMatch.waitForExistence(timeout: 5))
        shot(app, "a7-records")
    }

    /// 向上滑动直到元素出现并可点击
    @discardableResult
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) -> Bool {
        var n = 0
        while !(element.exists && element.isHittable) && n < maxSwipes {
            app.swipeUp()
            n += 1
        }
        return element.exists && element.isHittable
    }

    func testAddTodoFromAgenda() {
        let app = makeApp(seed: false)
        app.launch()
        tapTab(app, "日程")
        sleep(1)
        shot(app, "d1-agenda-empty")

        app.buttons["agendaAdd"].firstMatch.tap()
        let addTodo = app.buttons["加待办"].firstMatch
        XCTAssertTrue(addTodo.waitForExistence(timeout: 5))
        addTodo.tap()

        let title = app.textFields["todoTitle"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("订餐厅")
        shot(app, "d2-todo-edit")
        app.buttons["saveTodo"].tap()

        XCTAssertTrue(app.staticTexts["订餐厅"].firstMatch.waitForExistence(timeout: 5))
        shot(app, "d3-agenda-with-todo")
    }

    func testBrowseDemoData() {
        let app = makeApp(seed: true)
        app.launch()

        let tabs = ["后宫", "记录", "日程", "地图", "统计"]
        for (index, tab) in tabs.enumerated() {
            tapTab(app, tab)
            sleep(tab == "地图" ? 5 : 1)
            shot(app, "b\(index)-tab")
        }

        // 统计往下翻
        tapTab(app, "统计")
        app.swipeUp()
        sleep(1)
        shot(app, "b5-stats-more")

        // 设置
        let settings = app.buttons["openSettings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        sleep(1)
        shot(app, "b6-settings")
        app.buttons["完成"].firstMatch.tap()

        // 日程：待办模式
        tapTab(app, "日程")
        let segments = app.segmentedControls.firstMatch
        if segments.waitForExistence(timeout: 3) {
            segments.buttons.element(boundBy: 1).tap()
            sleep(1)
            shot(app, "b7-todos")
            segments.buttons.element(boundBy: 0).tap()
        }

        // 档案详情
        tapTab(app, "后宫")
        let mei = app.staticTexts["小美"].firstMatch
        XCTAssertTrue(mei.waitForExistence(timeout: 5))
        mei.tap()
        sleep(2)
        shot(app, "c1-detail")
        app.swipeUp()
        sleep(1)
        shot(app, "c2-detail-more")

        let cycleLink = app.buttons["经期日历与记录"].firstMatch
        if scrollTo(cycleLink, in: app) {
            cycleLink.tap()
            sleep(2)
            shot(app, "c3-cycle")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            sleep(1)
        }

        let timelineLink = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '查看完整时间线'")).firstMatch
        if scrollTo(timelineLink, in: app) {
            shot(app, "c4-detail-timeline")
            timelineLink.tap()
            sleep(2)
            shot(app, "c5-timeline")
        }
    }
}
