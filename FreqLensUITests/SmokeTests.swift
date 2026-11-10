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
        selectTab("持仓", in: app)
        XCTAssertTrue(app.staticTexts["当前仓位"].waitForExistence(timeout: 5))
        capture(app, "02-positions")
        openFirstPosition(in: app)
        XCTAssertTrue(app.navigationBars["交易详情"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["价格走势"].exists)
        capture(app, "03-trade-detail")
        app.navigationBars.buttons.firstMatch.tap()
        selectTab("分析", in: app)
        XCTAssertTrue(app.staticTexts["盈利因子"].waitForExistence(timeout: 5))
        capture(app, "04-analytics")
        selectTab("历史", in: app)
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
        selectTab("分析", in: app)
        XCTAssertTrue(app.staticTexts["periodTradeCount"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["periodTradeCount"].label, "90 笔已平仓")
        selectAppearance("浅色", in: app)
        capture(app, "11-warm-analytics")
        app.buttons["range-week"].tap()
        XCTAssertEqual(app.staticTexts["periodTradeCount"].label, "21 笔已平仓")
        selectAppearance("深色", in: app)
        capture(app, "06-dark-period-analytics")
        selectTab("历史", in: app)
        XCTAssertEqual(app.staticTexts["historyPeriodCount"].label, "21")
        app.buttons["range-custom"].tap()
        XCTAssertTrue(app.buttons["applyTimeRange"].waitForExistence(timeout: 5))
        app.buttons["应用时间筛选"].tap()
        XCTAssertTrue(app.staticTexts["customRangeLabel"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["historyPeriodCount"].label, "21")
        selectTab("总览", in: app)
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
        selectAppearance("跟随系统", in: app)
    }

    func testMonthlyCalendarAndHistoryDeletionPreview() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--tab", "2", "-appearance", "dark"]
        app.launch()
        let dailyChart = app.descendants(matching: .any).matching(identifier: "dailyChart").firstMatch
        for _ in 0..<6 {
            if dailyChart.exists && dailyChart.frame.maxY < app.tabBars.firstMatch.frame.minY - 50 { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.78))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.55)))
        }
        XCTAssertTrue(dailyChart.exists)
        dailyChart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["dailyReadout"].label.contains("笔平仓"))
        capture(app, "17-daily-profit")
        let month = app.staticTexts["calendarMonth"]
        let current = month.label
        // XCTest scrolls the actual button into view, avoiding overshoot from
        // fixed-distance swipes after inspecting the daily chart.
        app.buttons["calendarPreviousMonth"].tap()
        XCTAssertTrue(month.isHittable)
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
        selectTab("历史", in: app)
        tap(app.buttons["historyDeletionButton"], untilVisible: app.buttons["deletionCutoff"])
        tap(app.buttons["deletionCutoff"], untilVisible: app.buttons["1 个月前"])
        app.buttons["1 个月前"].tap()
        app.buttons["previewDeletion"].tap()
        XCTAssertTrue(app.staticTexts["deletionPreviewCount"].waitForExistence(timeout: 5))
        XCTAssertNotEqual(app.staticTexts["deletionPreviewCount"].label, "0 笔")
        XCTAssertTrue(app.staticTexts["演示预览 · 不执行删除"].exists)
        XCTAssertFalse(app.buttons["deleteHistoryRecords"].isEnabled)
        capture(app, "13-deletion-preview-demo")
    }

    func testRealizedAndPositionOutlookInBothAppearances() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        selectAppearance("深色", in: app)
        XCTAssertTrue(app.buttons["profitUnit-amount"].waitForExistence(timeout: 8))
        app.buttons["profitUnit-amount"].tap()
        let monthly = app.staticTexts["monthlyReturn"]
        for _ in 0..<4 {
            if monthly.isHittable && monthly.frame.maxY < app.tabBars.firstMatch.frame.minY - 100 { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.83))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.50)))
        }
        XCTAssertLessThan(monthly.frame.maxY, app.tabBars.firstMatch.frame.minY - 40)
        XCTAssertEqual(monthly.label, "+9.57%")
        XCTAssertEqual(app.staticTexts["annualReturn"].label, "+116.48%")
        XCTAssertEqual(app.staticTexts["profitEstimateValue"].label, "+2,679.84")
        let chart = app.descendants(matching: .any).matching(identifier: "profitChart").firstMatch
        let dateRange = app.staticTexts["profitViewport"].label
        // The final plot column represents current valuation, not a forecast date.
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.45)).tap()
        XCTAssertTrue(app.staticTexts["profitReadout"].label.contains("现价估值"))
        XCTAssertEqual(app.staticTexts["profitChartValue"].label, "+2,679.84")
        app.buttons["profitUnit-percent"].tap()
        XCTAssertEqual(app.staticTexts["profitEstimateValue"].label, "+10.72%")
        XCTAssertEqual(app.staticTexts["profitViewport"].label, dateRange)
        capture(app, "15-outlook-dark")
        selectAppearance("浅色", in: app)
        capture(app, "16-outlook-light")
        app.buttons["profitOutlookInfo"].tap()
        XCTAssertTrue(app.navigationBars["计算口径"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        app.buttons["profitUnit-amount"].tap()
        selectAppearance("深色", in: app)
    }

    private func selectTab(_ title: String, in app: XCUIApplication) {
        let button = app.tabBars.buttons[title]
        XCTAssertTrue(button.waitForExistence(timeout: 8))
        for _ in 0..<2 {
            button.tap()
            if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: button)], timeout: 3) == .completed { return }
        }
        XCTFail("Tab did not become selected: \(title)")
    }

    private func selectAppearance(_ title: String, in app: XCUIApplication) {
        let button = app.buttons["appearanceButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 8))
        if button.value as? String == title { return }
        let option = app.buttons[title]
        tap(button, untilVisible: option)
        option.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", title), object: button)], timeout: 5), .completed)
    }

    private func tap(_ source: XCUIElement, untilVisible target: XCUIElement) {
        for _ in 0..<2 {
            source.tap()
            if target.waitForExistence(timeout: 4) { return }
        }
        XCTFail("Expected control did not appear: \(target.identifier)")
    }

    private func openFirstPosition(in app: XCUIApplication) {
        let detail = app.navigationBars["交易详情"]
        for _ in 0..<2 {
            app.staticTexts["BTC/USDT"].firstMatch.tap()
            if detail.waitForExistence(timeout: 4) { return }
        }
        XCTFail("Position detail did not open")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testOverviewPercentSwitchReadoutAndPersistence() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        let value = app.staticTexts["profitChartValue"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        app.buttons["profitUnit-amount"].tap()
        XCTAssertEqual(value.label, "+2,393.43")
        let interval = app.staticTexts["profitViewport"].label
        app.buttons["profitUnit-percent"].tap()
        XCTAssertEqual(value.label, "+9.57%")
        XCTAssertEqual(app.staticTexts["profitViewport"].label, interval)
        XCTAssertTrue(app.staticTexts["profitReturnBasis"].exists)
        let chart = app.descendants(matching: .any).matching(identifier: "profitChart").firstMatch
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
            .press(forDuration: 0.2, thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 0.68, dy: 0.5)))
        XCTAssertTrue(value.label.hasSuffix("%"))
        XCTAssertNotEqual(value.label, "+9.57%")
        XCTAssertTrue(app.staticTexts["profitReadout"].label.contains("累计收益率"))
        let percentReadout = value.label
        app.buttons["profitUnit-amount"].tap()
        XCTAssertFalse(value.label.hasSuffix("%"))
        app.buttons["profitUnit-percent"].tap()
        XCTAssertEqual(value.label, percentReadout)
        capture(app, "14-profit-percent-readout")
        app.terminate()
        app.launch()
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        XCTAssertEqual(value.label, "+9.57%")
        app.buttons["range-week"].tap()
        XCTAssertEqual(value.label, "+2.04%")
        app.buttons["隐藏金额"].tap()
        XCTAssertEqual(value.label, "••••")
        XCTAssertEqual(app.staticTexts["monthlyReturn"].label, "••••")
        XCTAssertEqual(app.staticTexts["annualReturn"].label, "••••")
        XCTAssertEqual(app.staticTexts["profitEstimateValue"].label, "••••")
        app.buttons["显示金额"].tap()
        app.buttons["range-month"].tap()
        app.buttons["profitUnit-amount"].tap()
    }

    func testCandleChartReadsDirectlyInDarkMode() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--tab", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["当前仓位"].waitForExistence(timeout: 5))
        selectAppearance("深色", in: app)
        openFirstPosition(in: app)
        let candleChart = app.descendants(matching: .any).matching(identifier: "candlestickChart").firstMatch
        XCTAssertTrue(candleChart.waitForExistence(timeout: 8))
        for _ in 0..<4 {
            if candleChart.frame.maxY < app.tabBars.firstMatch.frame.minY - 20 { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.78))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.55)))
        }
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
