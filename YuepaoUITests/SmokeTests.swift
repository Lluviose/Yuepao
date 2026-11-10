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

    private func makeApp(seed: Bool, dark: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
                               "-appearance", dark ? "dark" : "light"]
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
        // 收起键盘看一眼整页，再点开「基本信息」里的 MBTI
        app.swipeUp()
        sleep(1)
        let mbti = app.buttons["MBTI E"].firstMatch
        if mbti.exists && mbti.isHittable { mbti.tap() }
        shot(app, "a2b-edit-basic")
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

        // 第一次记录会解锁成就，弹出庆祝
        let celebrate = app.buttons["dismissCelebration"].firstMatch
        XCTAssertTrue(celebrate.waitForExistence(timeout: 6))
        sleep(2)
        shot(app, "a6-celebration")
        var dismissed = 0
        while celebrate.waitForExistence(timeout: 2) && dismissed < 8 {
            celebrate.tap()
            dismissed += 1
            sleep(1)
        }
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

        let tabs = ["后宫", "记录", "日程", "地图", "成就"]
        for (index, tab) in tabs.enumerated() {
            tapTab(app, tab)
            sleep(tab == "地图" ? 5 : 1)
            shot(app, "b\(index)-tab")
        }

        // 记录详情 + 记一次表单（快速选人）
        tapTab(app, "记录")
        let personFilter = app.buttons["filter-阿雪"].firstMatch
        if personFilter.waitForExistence(timeout: 3) {
            personFilter.tap()
            sleep(1)
            shot(app, "b1b-records-filter")
        }
        let firstRecord = app.staticTexts["阿雪"].firstMatch
        if firstRecord.waitForExistence(timeout: 5) {
            firstRecord.tap()
            sleep(2)
            shot(app, "e1-record-detail")
            app.swipeUp()
            sleep(1)
            shot(app, "e1b-record-detail-more")
            app.swipeUp()
            sleep(1)
            shot(app, "e1c-record-detail-end")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            sleep(1)
        }
        app.buttons["addEncounter"].firstMatch.tap()
        let quickPick = app.buttons["小美"].firstMatch
        if quickPick.waitForExistence(timeout: 5) {
            quickPick.tap()
            sleep(1)
            shot(app, "e2-record-form")
            // 她的特质：原地点开
            let traits = app.buttons["traits-小美"].firstMatch
            if traits.waitForExistence(timeout: 3) {
                traits.tap()
                sleep(1)
                shot(app, "e2b-record-traits")
                traits.tap()
                sleep(1)
            }
            // 过程：强度、她高潮
            let intensity = app.buttons["intensity-3"].firstMatch
            if scrollTo(intensity, in: app) {
                intensity.tap()
                let plus = app.buttons["orgasms-plus"].firstMatch
                if plus.exists && plus.isHittable { plus.tap() }
                sleep(1)
                shot(app, "e2c-record-process")
            }
            // 道具：点开选两个
            let toys = app.buttons["tags-toys"].firstMatch
            if scrollTo(toys, in: app) {
                toys.tap()
                sleep(1)
                // 点开后往上滚到能看到「眼罩」（束缚组），震动组的「跳蛋」也在同一屏
                let blindfold = app.buttons["眼罩"].firstMatch
                if scrollTo(blindfold, in: app, maxSwipes: 3) {
                    blindfold.tap()
                    let vibe = app.buttons["跳蛋"].firstMatch
                    if vibe.exists && vibe.isHittable { vibe.tap() }
                }
                sleep(1)
                shot(app, "e2d-record-toys")
            }
            // 安全和感受
            let feedback = app.buttons["tags-feedback"].firstMatch
            if scrollTo(feedback, in: app) {
                let condom = app.buttons["protection-condom"].firstMatch
                if condom.exists && condom.isHittable { condom.tap() }
                let star = app.buttons["rating-4"].firstMatch
                if star.exists && star.isHittable { star.tap() }
                sleep(1)
                shot(app, "e2e-record-feeling")
            }
        }
        app.buttons["取消"].firstMatch.tap()
        let discard = app.buttons["放弃修改"].firstMatch
        if discard.waitForExistence(timeout: 3) {
            shot(app, "e3-discard")
            discard.tap()
        }
        sleep(1)

        // 成就页往下翻
        tapTab(app, "成就")
        sleep(1)
        app.swipeUp()
        sleep(1)
        shot(app, "b5-hub-more")

        // 最近解锁里点一枚奖章看详情
        let recentMedal = app.buttons.matching(NSPredicate(format: "label CONTAINS '安全第一' OR label CONTAINS '左拥右抱'")).firstMatch
        if recentMedal.waitForExistence(timeout: 3) && recentMedal.isHittable {
            recentMedal.tap()
            sleep(2)
            shot(app, "i2-achievement-detail")
            let close = app.buttons["closeAchievement"].firstMatch
            if close.waitForExistence(timeout: 3) { close.tap() }
            sleep(1)
        }

        // 完整统计
        let stats = app.buttons["openStats"].firstMatch
        if scrollTo(stats, in: app) {
            stats.tap()
            sleep(2)
            shot(app, "b8-stats")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            sleep(1)
        }

        // 收藏：图鉴 / 印章 / 心愿 / 回顾
        app.swipeDown()
        app.swipeDown()
        sleep(1)
        let codex = app.buttons["codexCard"].firstMatch
        if scrollTo(codex, in: app) {
            codex.tap()
            sleep(2)
            shot(app, "i3-codex")
            let codexSegments = app.segmentedControls.firstMatch
            if codexSegments.waitForExistence(timeout: 3) {
                codexSegments.buttons["道具"].tap()
                sleep(1)
                shot(app, "i3c-toys")
                codexSegments.buttons["星座"].tap()
                sleep(1)
                shot(app, "i3b-zodiac")
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
            sleep(1)
        }
        let stamps = app.buttons["stampsCard"].firstMatch
        if scrollTo(stamps, in: app) {
            stamps.tap()
            sleep(2)
            shot(app, "i4-stamps")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            sleep(1)
        }
        let wishes = app.buttons["wishCard"].firstMatch
        if scrollTo(wishes, in: app) {
            wishes.tap()
            sleep(2)
            shot(app, "i5-wishes")
            let addWish = app.buttons["addWish"].firstMatch
            if addWish.waitForExistence(timeout: 3) {
                addWish.tap()
                sleep(1)
                shot(app, "i5b-wish-composer")
                app.buttons["取消"].firstMatch.tap()
                sleep(1)
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
            sleep(1)
        }
        let review = app.buttons["reviewCard"].firstMatch
        if scrollTo(review, in: app) {
            review.tap()
            sleep(2)
            shot(app, "j0-review-cover")
            for page in 1...7 {
                app.swipeLeft()
                sleep(2)
                if [1, 3, 5, 7].contains(page) { shot(app, "j\(page)-review") }
            }
            app.buttons["closeReview"].firstMatch.tap()
            sleep(1)
        }

        // 成就馆
        app.swipeDown()
        app.swipeDown()
        sleep(1)
        let levelCard = app.buttons["levelCard"].firstMatch
        if levelCard.waitForExistence(timeout: 3) {
            levelCard.tap()
            sleep(2)
            shot(app, "i1-achievements")
            app.swipeUp()
            sleep(1)
            shot(app, "i1b-achievements-more")
            let medal = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS '初试云雨'")).firstMatch
            if medal.waitForExistence(timeout: 3) {
                app.swipeDown()
                sleep(1)
                if medal.isHittable {
                    medal.tap()
                    sleep(2)
                    shot(app, "i2-achievement-detail")
                    let close = app.buttons["closeAchievement"].firstMatch
                    if close.waitForExistence(timeout: 3) { close.tap() }
                    sleep(1)
                }
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
            sleep(1)
        }

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

        let memo = app.buttons["quickMemo"].firstMatch
        if memo.waitForExistence(timeout: 3) {
            memo.tap()
            sleep(1)
            app.typeText("她说下周想去看海")
            shot(app, "g1-note-sheet")
            app.buttons["取消"].firstMatch.tap()
            sleep(1)
        }

        app.swipeUp()
        sleep(1)
        shot(app, "c2-detail-more")

        let cycleLink = app.buttons["经期日历与记录"].firstMatch
        if scrollTo(cycleLink, in: app) {
            cycleLink.tap()
            sleep(2)
            shot(app, "c3-cycle")
            let addPeriod = app.buttons["补记一次"].firstMatch
            if scrollTo(addPeriod, in: app) {
                addPeriod.tap()
                sleep(1)
                shot(app, "g2-period-sheet")
                app.buttons["取消"].firstMatch.tap()
                sleep(1)
            }
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

    /// 档案里的亲密档案：特质（恋痛等）、安全词、底线，以及编辑页里的标签选择
    func testIntimacyProfile() {
        let app = makeApp(seed: true)
        app.launch()
        tapTab(app, "后宫")
        let xue = app.staticTexts["阿雪"].firstMatch
        XCTAssertTrue(xue.waitForExistence(timeout: 5))
        xue.tap()
        sleep(2)
        let header = app.staticTexts["亲密档案"].firstMatch
        if scrollTo(header, in: app, maxSwipes: 10) {
            app.swipeUp()
            sleep(1)
            shot(app, "c7-intimacy")
        }
        let menu = app.buttons["girlMenu"].firstMatch
        if menu.waitForExistence(timeout: 3) {
            menu.tap()
            let edit = app.buttons["编辑档案"].firstMatch
            if edit.waitForExistence(timeout: 3) {
                edit.tap()
                sleep(2)
                // 编辑页：顶部是头像、代号、关系、位分，其余卡片收起只显示摘要
                shot(app, "c9-edit-top")
                app.swipeUp()
                sleep(1)
                shot(app, "c10-edit-folded")
                let harem = app.buttons["fold-harem"].firstMatch
                if scrollTo(harem, in: app) {
                    harem.tap()
                    sleep(1)
                    shot(app, "c11-edit-harem")
                    harem.tap()
                    sleep(1)
                }
                let intimacy = app.buttons["fold-intimacy"].firstMatch
                if scrollTo(intimacy, in: app) {
                    intimacy.tap()
                    sleep(1)
                    let traits = app.buttons["tags-traits"].firstMatch
                    if scrollTo(traits, in: app) {
                        traits.tap()
                        sleep(1)
                        shot(app, "c8-intimacy-edit")
                    }
                }
                // 顶上的分区索引：点「身材」会展开那张卡片并滚过去
                let rail = app.buttons["rail-body"].firstMatch
                if rail.waitForExistence(timeout: 3) && rail.isHittable {
                    rail.tap()
                    sleep(2)
                    shot(app, "c12-edit-rail")
                }
            }
        }
    }

    /// 档案页：「更多」里是不常用的几种记录；小节标题上的笔直接打开编辑页里对应的那一块
    func testEditInPlace() {
        let app = makeApp(seed: true)
        app.launch()
        tapTab(app, "后宫")
        let mei = app.staticTexts["小美"].firstMatch
        XCTAssertTrue(mei.waitForExistence(timeout: 5))
        mei.tap()
        sleep(2)
        let more = app.buttons["quickMore"].firstMatch
        if more.waitForExistence(timeout: 3) && more.isHittable {
            more.tap()
            sleep(1)
            shot(app, "c14-quick-more")
            // 点菜单外面收起
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
            sleep(1)
        }
        let editBody = app.buttons["编辑身材外貌"].firstMatch
        if scrollTo(editBody, in: app, maxSwipes: 10) {
            editBody.tap()
            sleep(3)
            shot(app, "c13-edit-focus")
        }
    }

    /// 照片视频：记录里的照片墙、全屏看照片 / 实况 / 视频、相册页、档案相册
    func testMediaGallery() {
        let app = makeApp(seed: true)
        app.launch()
        // 演示用的实况和视频在后台生成，等一下
        sleep(5)
        tapTab(app, "记录")
        let filter = app.buttons["filter-阿雪"].firstMatch
        if filter.waitForExistence(timeout: 3) { filter.tap() }
        let record = app.staticTexts["阿雪"].firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.tap()
        sleep(2)
        let first = app.buttons["media-0"].firstMatch
        if scrollTo(first, in: app, maxSwipes: 3) {
            sleep(1)
            shot(app, "m1-record-media")
            first.tap()
            sleep(2)
            shot(app, "m2-viewer-photo")
            app.swipeLeft()
            sleep(2)
            shot(app, "m3-viewer-live")
            app.swipeLeft()
            sleep(3)
            shot(app, "m4-viewer-video")
            let close = app.buttons["closeViewer"].firstMatch
            if close.waitForExistence(timeout: 3) && close.isHittable {
                close.tap()
                sleep(1)
            }
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        sleep(1)

        // 相册：全部照片视频按月份排
        tapTab(app, "成就")
        sleep(1)
        let album = app.buttons["openAlbum"].firstMatch
        if scrollTo(album, in: app) {
            album.tap()
            sleep(2)
            shot(app, "m5-album")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            sleep(1)
        }

        // 档案里的相册
        tapTab(app, "后宫")
        let mei = app.staticTexts["小美"].firstMatch
        if mei.waitForExistence(timeout: 5) {
            mei.tap()
            sleep(2)
            let albumLink = app.buttons["openGirlAlbum"].firstMatch
            if scrollTo(albumLink, in: app, maxSwipes: 12) {
                sleep(1)
                shot(app, "m6-profile-photos")
                if albumLink.isHittable {
                    albumLink.tap()
                    sleep(2)
                    shot(app, "m7-girl-album")
                }
            }
        }
    }

    /// 万一弹出了详情之类的页面，往下拖关掉，回到地图
    private func dismissSheetIfNeeded(_ app: XCUIApplication) {
        let bar = app.navigationBars.firstMatch
        if bar.exists {
            bar.swipeDown(velocity: .fast)
            sleep(1)
        }
    }

    func testMapModule() {
        let app = makeApp(seed: true)
        app.launch()
        tapTab(app, "地图")
        sleep(4)
        shot(app, "k1-map")

        // 足迹总览，点城市飞过去
        let summary = app.buttons["mapSummary"].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        summary.tap()
        sleep(2)
        shot(app, "k2-overview")
        let city = app.buttons["city-上海"].firstMatch
        if city.waitForExistence(timeout: 3) {
            city.tap()
        } else {
            app.buttons["closeOverview"].firstMatch.tap()
        }
        sleep(3)
        shot(app, "k3-city")

        // 点一个人：底部卡片、连线，其余变淡
        let pin = app.descendants(matching: .any)["pin-小美"].firstMatch
        if pin.waitForExistence(timeout: 5) && pin.isHittable {
            pin.tap()
            sleep(2)
            shot(app, "k4-focus")
            // 在卡片下半部（指标区，不是按钮）往左拖，切到下一张
            let card = app.descendants(matching: .any)["mapCard-小美"].firstMatch
            if card.waitForExistence(timeout: 3) {
                let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.78))
                let end = card.coordinate(withNormalizedOffset: CGVector(dx: -0.55, dy: 0.78))
                start.press(forDuration: 0.1, thenDragTo: end)
                sleep(2)
                shot(app, "k5-next-card")
            }
            dismissSheetIfNeeded(app)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.3)).tap()
            sleep(1)
        }

        // 地点和热力
        dismissSheetIfNeeded(app)
        app.buttons["mapMode-places"].firstMatch.tap()
        sleep(2)
        shot(app, "k6-places")
        app.buttons["mapMode-heat"].firstMatch.tap()
        sleep(3)
        shot(app, "k7-heat")
        app.buttons["mapMode-all"].firstMatch.tap()
        sleep(1)

        // 足迹回放
        let playback = app.buttons["mapPlayback"].firstMatch
        if playback.waitForExistence(timeout: 3) {
            playback.tap()
            sleep(5)
            shot(app, "k8-playback")
            sleep(9)
            shot(app, "k9-playback-end")
            let close = app.buttons["playbackClose"].firstMatch
            if close.waitForExistence(timeout: 3) {
                close.tap()
            }
            sleep(2)
        }

        // 长按空白处添加地点
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).press(forDuration: 1.0)
        sleep(2)
        shot(app, "k10-draft")
        let create = app.buttons["draftCreate"].firstMatch
        if create.waitForExistence(timeout: 3) {
            create.tap()
            sleep(2)
            shot(app, "k11-new-place")
        }
    }

    func testDarkMode() {
        let app = makeApp(seed: true, dark: true)
        app.launch()
        for (index, tab) in ["后宫", "日程", "成就"].enumerated() {
            tapTab(app, tab)
            sleep(1)
            shot(app, "f\(index)-dark")
        }
        tapTab(app, "地图")
        sleep(4)
        shot(app, "f4-dark-map")
        let heat = app.buttons["mapMode-heat"].firstMatch
        if heat.waitForExistence(timeout: 3) {
            heat.tap()
            sleep(3)
            shot(app, "f5-dark-heat")
            app.buttons["mapMode-all"].firstMatch.tap()
        }
        tapTab(app, "后宫")
        let mei = app.staticTexts["小美"].firstMatch
        if mei.waitForExistence(timeout: 5) {
            mei.tap()
            sleep(2)
            shot(app, "f3-dark-detail")
        }
        tapTab(app, "记录")
        let record = app.staticTexts["阿雪"].firstMatch
        if record.waitForExistence(timeout: 5) {
            record.tap()
            sleep(2)
            shot(app, "f6-dark-record")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            sleep(1)
        }
        app.buttons["addEncounter"].firstMatch.tap()
        let pick = app.buttons["阿雪"].firstMatch
        if pick.waitForExistence(timeout: 5) {
            pick.tap()
            sleep(1)
            shot(app, "f7-dark-form")
            // 照上次的填：地点和玩法一下填好，顶上的索引跟着亮起来
            let reuse = app.buttons["reuseLast"].firstMatch
            if reuse.waitForExistence(timeout: 3) && reuse.isHittable {
                reuse.tap()
                sleep(1)
                shot(app, "f8-dark-reuse")
            }
        }
    }

    func testLockScreen() {
        let app = makeApp(seed: false)
        app.launchArguments.append("-previewLock")
        app.launch()
        sleep(2)
        shot(app, "h1-lock")
    }
}
