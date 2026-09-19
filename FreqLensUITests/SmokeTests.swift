import XCTest

@MainActor
final class SmokeTests: XCTestCase {
    func testNavigationAndConnectionValidation() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["assetTitle"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["演示数据"].exists)
        XCTAssertFalse(app.staticTexts["已连接"].exists)
        XCTAssertFalse(app.navigationBars["总览"].exists)
        capture(app, "01-overview")
        app.tabBars.buttons["持仓"].tap()
        XCTAssertTrue(app.staticTexts["当前仓位"].waitForExistence(timeout: 5))
        capture(app, "02-positions")
        app.staticTexts["BTC/USDT"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["交易详情"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["价格走势"].exists)
        capture(app, "03-trade-detail")
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["分析"].tap()
        XCTAssertTrue(app.staticTexts["盈利因子"].waitForExistence(timeout: 5))
        capture(app, "04-analytics")
        app.tabBars.buttons["历史"].tap()
        XCTAssertTrue(app.staticTexts["historyPeriodCount"].waitForExistence(timeout: 5))
        capture(app, "05-history")
        app.buttons["serverButton"].tap()
        XCTAssertTrue(app.textFields["serverAddress"].waitForExistence(timeout: 5))
        let address = app.textFields["serverAddress"]
        address.tap(); address.typeText("invalid-address")
        let user = app.textFields["serverUsername"]
        user.tap(); user.typeText("test")
        let password = app.secureTextFields["serverPassword"]
        password.tap(); password.typeText("test")
        app.swipeUp()
        app.buttons["connectButton"].tap()
        XCTAssertTrue(app.staticTexts["connectionError"].waitForExistence(timeout: 5))
    }

    func testSharedTimeFilterChartReadoutAndDarkAppearance() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        app.tabBars.buttons["分析"].tap()
        XCTAssertTrue(app.staticTexts["periodTradeCount"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["periodTradeCount"].label, "90 笔已平仓")
        app.buttons["appearanceButton"].tap()
        app.buttons["浅色"].tap()
        capture(app, "11-warm-analytics")
        app.buttons["range-week"].tap()
        XCTAssertEqual(app.staticTexts["periodTradeCount"].label, "21 笔已平仓")
        app.buttons["appearanceButton"].tap()
        app.buttons["深色"].tap()
        capture(app, "06-dark-period-analytics")
        app.tabBars.buttons["历史"].tap()
        XCTAssertEqual(app.staticTexts["historyPeriodCount"].label, "21")
        app.buttons["range-custom"].tap()
        XCTAssertTrue(app.buttons["applyTimeRange"].waitForExistence(timeout: 5))
        app.buttons["应用时间筛选"].tap()
        XCTAssertTrue(app.staticTexts["customRangeLabel"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["historyPeriodCount"].label, "21")
        app.tabBars.buttons["总览"].tap()
        app.buttons["range-month"].tap()
        XCTAssertFalse(app.buttons["chartMode-read"].exists)
        XCTAssertFalse(app.buttons["chartMode-browse"].exists)
        XCTAssertFalse(app.buttons["chartWindowMenu"].exists)
        let chart = app.descendants(matching: .any).matching(identifier: "profitChart").firstMatch
        XCTAssertTrue(chart.exists)
        let start = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
        let end = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.5))
        let viewport = app.staticTexts["profitViewport"].label
        start.press(forDuration: 0.2, thenDragTo: end)
        XCTAssertEqual(app.staticTexts["profitViewport"].label, viewport)
        XCTAssertTrue(app.staticTexts["profitReadout"].label.contains("累计收益"))
        capture(app, "07-dark-chart-selection")
        app.buttons["appearanceButton"].tap()
        app.buttons["跟随系统"].tap()
    }

    func testMonthlyCalendarAndHistoryDeletionPreview() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--tab", "2", "-appearance", "dark"]
        app.launch()
        let month = app.staticTexts["calendarMonth"]
        for _ in 0..<6 {
            if month.exists && month.isHittable { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.8))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.25)))
        }
        XCTAssertTrue(month.isHittable)
        let current = month.label
        app.buttons["calendarPreviousMonth"].tap()
        XCTAssertNotEqual(month.label, current)
        let summary = app.descendants(matching: .any).matching(identifier: "calendarSummary").firstMatch
        for _ in 0..<4 {
            if summary.isHittable { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.8))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.55)))
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: Date())!
        let startOfMonth = calendar.dateInterval(of: .month, for: previousMonth)!.start
        let offset = (calendar.component(.weekday, from: startOfMonth) + 5) % 7
        let weekdays = ["一", "二", "三", "四", "五", "六", "日"]
        for day in 1...7 {
            let cell = app.buttons["calendarDay-\(day)"]
            XCTAssertTrue(cell.exists, "The first week must contain every date")
            let weekday = app.staticTexts["calendarWeekday-\(weekdays[(offset + day - 1) % 7])"]
            XCTAssertEqual(cell.frame.midX, weekday.frame.midX, accuracy: 2, "Date must align with its weekday")
        }
        let lastDay = calendar.range(of: .day, in: .month, for: previousMonth)!.count
        XCTAssertTrue(app.buttons["calendarDay-\(lastDay)"].exists)
        capture(app, "12-previous-month-calendar")
        app.buttons["calendarNextMonth"].tap()
        XCTAssertEqual(month.label, current)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.3))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.75)))
        XCTAssertTrue(app.tabBars.buttons["历史"].waitForExistence(timeout: 5))
        app.tabBars.buttons["历史"].tap()
        app.buttons["historyDeletionButton"].tap()
        app.buttons["deletionCutoff"].tap()
        app.buttons["1 个月前"].tap()
        app.buttons["previewDeletion"].tap()
        XCTAssertTrue(app.staticTexts["deletionPreviewCount"].waitForExistence(timeout: 5))
        XCTAssertNotEqual(app.staticTexts["deletionPreviewCount"].label, "0 笔")
        XCTAssertTrue(app.staticTexts["演示预览 · 不执行删除"].exists)
        XCTAssertFalse(app.buttons["deleteHistoryRecords"].isEnabled)
        capture(app, "13-deletion-preview-demo")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCandleChartReadsDirectlyInDarkMode() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--tab", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["当前仓位"].waitForExistence(timeout: 5))
        app.buttons["appearanceButton"].tap()
        app.buttons["深色"].tap()
        app.staticTexts["BTC/USDT"].firstMatch.tap()
        app.swipeUp()
        XCTAssertFalse(app.buttons["candlesMode-read"].exists)
        XCTAssertFalse(app.buttons["candlesMode-browse"].exists)
        XCTAssertFalse(app.buttons["candlesWindowMenu"].exists)
        let chart = app.descendants(matching: .any).matching(identifier: "candlestickChart").firstMatch
        let start = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
        let end = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: end)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "candleReadout").firstMatch.exists)
        capture(app, "09-dark-candle-selection")

    }
}
