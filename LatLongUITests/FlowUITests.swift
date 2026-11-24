import XCTest

final class FlowUITests: XCTestCase {
    private enum StoreLanguage: String, CaseIterable {
        case ja, en, zhHans = "zh-Hans"

        var locale: String {
            switch self {
            case .ja: return "ja_JP"
            case .en: return "en_US"
            case .zhHans: return "zh_CN"
            }
        }
    }

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ args: [String] = [], language: StoreLanguage = .ja, reset: Bool = true,
                        environment: [String: String] = [:]) {
        if app.state != .notRunning { app.terminate() }
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(\(language.rawValue))",
                               "-AppleLocale", language.locale] + (reset ? ["-reset"] : []) + args
        app.launchEnvironment = environment
        app.launch()
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func tap(_ id: String) {
        let query = app.buttons.matching(identifier: id)
        let deadline = Date().addingTimeInterval(2)
        var enabledButton: XCUIElement?
        repeat {
            let buttons = query.allElementsBoundByIndex.filter { $0.exists && $0.isEnabled }
            if let button = buttons.first(where: { $0.isHittable }) {
                button.tap()
                return
            }
            enabledButton = buttons.first
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        } while Date() < deadline
        guard let button = enabledButton, button.exists, button.isEnabled else {
            XCTFail("Could not find an enabled button: \(id)")
            return
        }
        button.tap()
    }

    private func expect(_ id: String, timeout: TimeInterval = 8) {
        XCTAssertTrue(element(id).waitForExistence(timeout: timeout), id)
    }

    private func expectText(_ id: String, includes text: String) {
        let target = element(id)
        let predicate = NSPredicate { _, _ in
            target.exists && (target.label.contains(text) || (target.value as? String)?.contains(text) == true)
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 8)
        var message = "\(id): \(text)"
        if result != .completed {
            message += target.exists ? " (label: \(target.label), value: \(target.value ?? "nil"))" : " (element missing)"
        }
        XCTAssertEqual(result, .completed, message)
    }

    private func shot(_ name: String) {
        let image = app.screenshot()
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func toggle(_ id: String) {
        let control = app.switches[id].firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 8))
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertEqual(control.value as? String, "1")
    }

    func testReadCopySaveRenameAndTwoTapExport() {
        launch(language: .en)
        expectText("reading.latitude", includes: "35.713842")
        XCTAssertEqual(app.alerts.count, 0)
        tap("home.copy")
        expectText("feedback.notice", includes: "Copied")
        tap("format.dms")
        expectText("reading.latitude", includes: "35°")
        tap("home.save")
        expect("home.saved")
        tap("saved.rename")
        let name = app.textFields["point.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        name.tap()
        name.typeText("Water stop")
        tap("name.save")
        expectText("home.saved", includes: "Water stop")
        tap("home.export")
        expectText("export.count", includes: "1")
        tap("export.csv")
        expect("share.requested")
        tap("sheet.done")
        tap("home.points")
        tap("point.row.1")
        expectText("point.title", includes: "Water stop")
    }

    func testLowAccuracyAndDeniedPermission() {
        launch(["-fix", "low"], language: .en)
        expectText("location.state", includes: "Low accuracy")
        expectText("home.save", includes: "Save at this accuracy")
        tap("home.save")
        expect("home.saved")

        launch(["-fix", "denied"], language: .en)
        expectText("location.state", includes: "Location access is off")
        XCTAssertFalse(app.buttons["home.copy"].isEnabled)
        XCTAssertFalse(app.buttons["home.save"].isEnabled)
        expect("location.settings")
        tap("home.points")
        expect("points.filters")
    }

    func testRecordsSurviveRelaunchInIsolatedSession() {
        let environment = ["LATLONG_TEST_SESSION": UUID().uuidString]
        launch(language: .en, reset: false, environment: environment)
        tap("home.save")
        expect("home.saved")
        launch(language: .en, reset: false, environment: environment)
        tap("home.points")
        expect("point.row.1")
    }

    func testCreateProjectFilterAndDelete() {
        launch(language: .en)
        tap("home.project")
        tap("project.new")
        let field = app.textFields["project.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        field.typeText("North Trail")
        tap("name.save")
        expectText("home.project", includes: "North Trail")
        tap("home.save")
        expect("home.saved")
        tap("home.points")
        tap("points.filters")
        expect("points.quality")
        expect("points.source")
        tap("point.row.1")
        tap("point.delete")
        var alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 8))
        alert.buttons["Cancel"].tap()
        expect("point.title")
        tap("point.delete")
        alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 8))
        alert.buttons["Delete"].tap()
        expect("points.filters")
        XCTAssertFalse(app.buttons["point.row.1"].exists)
    }

    func testCodeImportAndDuplicateRejection() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "coordinate": ["latitude": 35.713842, "longitude": 139.772461],
            "name": "Meeting point", "accuracy": 6, "quality": "good"
        ])
        let code = "LL1:" + data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        launch(language: .en, environment: ["LATLONG_TEST_IMPORT": "\n" + code + "\n"])
        expect("home.importFile")
        for index in 0..<2 {
            tap("home.import")
            let paste = app.buttons["import.paste"]
            if paste.exists { tap("import.paste") }
            else { tap("Paste") }
            expectText("import.previewName", includes: "Meeting point")
            tap("import.add")
            expectText("feedback.notice", includes: index == 0 ? "added" : "already saved")
            tap("sheet.done")
        }
        tap("home.points")
        tap("point.row.1")
        tap("point.code")
        tap("code.copy")
        expectText("feedback.notice", includes: "Copied")
        tap("code.file")
        expect("share.requested")
    }

    func testPointListSharesInThreeTapsWithPrivateDefaults() {
        launch(["-demo"], language: .en)
        tap("home.points")
        tap("point.share.1")
        expect("card.preview")
        XCTAssertEqual(app.switches["card.coordinates"].value as? String, "0")
        XCTAssertEqual(app.switches["card.name"].value as? String, "0")
        XCTAssertEqual(app.switches["card.accuracy"].value as? String, "0")
        tap("card.share")
        expect("share.requested")
    }

    func testWaypointFileFromHomePreviewsBeforeAdding() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "coordinate": ["latitude": 35.7, "longitude": 139.7], "name": "File waypoint"
        ])
        let code = "LL1:" + data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        launch(language: .en, environment: ["LATLONG_TEST_FILE": code])
        tap("home.importFile")
        expectText("import.previewName", includes: "File waypoint")
        tap("sheet.done")
        tap("home.points")
        expect("points.filters")
        XCTAssertFalse(app.buttons["point.row.1"].exists)
        tap("sheet.done")
        tap("home.importFile")
        tap("import.add")
        expectText("feedback.notice", includes: "added")
        tap("sheet.done")
        tap("home.points")
        expectText("point.row.1", includes: "File waypoint")
    }

    func testMilestoneAppearsAtTenAndCardCanBeClosed() {
        launch(["-demo"], language: .en)
        XCTAssertFalse(app.buttons["home.milestone"].exists)
        tap("home.save")
        expect("home.saved")
        tap("home.milestone")
        expect("card.preview")
        tap("card.share")
        expect("share.requested")
        tap("sheet.done")
        expect("home.milestone")
    }

    func testExpiredKeepsOldExportAndNewCapture() {
        launch(["-expired", "-demo"], language: .en)
        expectText("home.project", includes: "Unfiled")
        tap("home.save")
        expectText("home.saved", includes: "004")
        tap("home.export")
        expectText("export.count", includes: "3")
        tap("export.filters")
        expect("export.quality")
        XCTAssertFalse(element("export.source").exists)
        tap("export.gpx")
        expect("share.requested")
        tap("sheet.done")
        tap("home.project")
        tap("project.new")
        expect("paywall.title")
    }

    func testExportFilterCanExcludeLowAccuracyRows() {
        launch(["-demo"], language: .en)
        tap("home.export")
        expectText("export.count", includes: "3")
        tap("export.filters")
        let filter = element("export.quality")
        XCTAssertTrue(filter.waitForExistence(timeout: 8))
        filter.tap()
        let good = app.buttons["Good accuracy"].firstMatch
        XCTAssertTrue(good.waitForExistence(timeout: 8))
        good.tap()
        expectText("export.count", includes: "2")
        tap("export.kml")
        expect("share.requested")
    }

    func testStoreScreenshots() {
        for language in StoreLanguage.allCases {
            launch(["-demo"], language: language)
            expectText("reading.latitude", includes: "35.713842")
            expectText("home.project", includes: language == .ja ? "上野公園" : language == .en ? "Ueno Park" : "上野公园")
            shot("store-\(language.rawValue)-01-home")
            tap("home.save")
            expect("home.saved")
            shot("store-\(language.rawValue)-02-save")

            launch(["-demo", "-fix", "low", "-offline"], language: language)
            expectText("reading.latitude", includes: "35.713900")
            shot("store-\(language.rawValue)-03-low")

            launch(["-demo"], language: language)
            tap("home.export")
            expectText("export.count", includes: "3")
            expect("export.gpx")
            shot("store-\(language.rawValue)-04-export")
            tap("sheet.done")
            tap("home.points")
            tap("point.row.1")
            tap("point.card")
            expect("card.preview")
            XCTAssertEqual(app.switches["card.coordinates"].value as? String, "0")
            XCTAssertEqual(app.switches["card.name"].value as? String, "0")
            XCTAssertEqual(app.switches["card.accuracy"].value as? String, "0")
            toggle("card.coordinates")
            expectText("card.preview", includes: "35.713842")
            shot("store-\(language.rawValue)-05-card")
        }
    }

    func testPaywallScreenshot() {
        launch(["-paywall"], language: .zhHans)
        expect("paywall.title")
        expect("paywall.buy")
        expect("paywall.restore")
        expect("paywall.trial")
        shot("paid-01-paywall")
    }

    func testReviewDemo() {
        continueAfterFailure = true
        launch(language: .en)
        expectText("reading.latitude", includes: "35.713842")
        sleep(3)
        tap("home.copy"); sleep(2)
        tap("format.dms"); sleep(2)
        tap("home.save"); expect("home.saved"); sleep(2)
        tap("saved.rename")
        let name = app.textFields["point.name"]
        if name.waitForExistence(timeout: 8) {
            name.tap(); name.typeText("Water stop"); sleep(1)
            tap("name.save")
        }
        sleep(2)
        tap("home.save"); sleep(2)
        tap("home.export"); sleep(3)
        tap("export.csv"); sleep(3)
        tap("sheet.done"); sleep(1)
        tap("home.points"); sleep(3)
        tap("point.row.1"); sleep(3)
        tap("point.back"); sleep(1)
        tap("sheet.done"); sleep(1)
        tap("home.settings"); sleep(2)
        tap("settings.purchase"); sleep(4)
    }
}
