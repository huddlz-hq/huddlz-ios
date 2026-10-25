import XCTest

/// The huddl page keeps its name and RSVP in reach while reading, and lets people share it or add it to their calendar.
@MainActor
final class HuddlPageUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testTheHuddlsNameMovesIntoTheBarOnceItsTitleScrollsAway() {
        let app = openPicnic()
        let barTitle = app.navigationBars.staticTexts["Picnic in the park"]
        XCTAssertFalse(barTitle.exists)
        app.swipeUp()
        XCTAssertTrue(barTitle.waitForExistence(timeout: 5))
        app.swipeDown()
        app.swipeDown()
        XCTAssertTrue(barTitle.waitForNonExistence(timeout: 5))
    }

    func testTheRSVPActionStaysOnScreenWhileReadingTheDescription() {
        let app = openPicnic()
        // The description is one text element; read until its last line is on screen.
        let about = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "garage on Oak Street")).firstMatch
        let screen = app.windows.firstMatch.frame
        for _ in 0..<4 where about.frame.maxY > screen.maxY - 120 { app.swipeUp() }
        XCTAssertLessThan(about.frame.maxY, screen.maxY - 120)
        XCTAssertTrue(app.buttons["Sign in to RSVP"].isHittable)
    }

    func testShareOffersTheHuddlsWebPage() {
        let app = openPicnic()
        app.buttons["Share"].tap()
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        let labelled = { (text: String) in sheet.descendants(matching: .any).matching(NSPredicate(format: "label == %@", text)).firstMatch }
        XCTAssertTrue(labelled("Picnic in the park").exists)
        // Reading List takes only web pages, so it appears only when the share is the huddl's link.
        XCTAssertTrue(labelled("Add to Reading List").exists)
    }

    func testAddToCalendarOpensANewEventFilledInWithTheHuddl() {
        let app = openPicnic()
        app.buttons["Add to Calendar"].tap()
        let title = app.textFields.matching(NSPredicate(format: "value == %@", "Picnic in the park")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        // Leaving without saving asks to discard the filled-in event, then returns to the huddl.
        app.buttons["Cancel"].tap()
        app.buttons["Discard Changes"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add to Calendar"].isHittable)
    }

    func testAHuddlInAnotherTimeZoneNamesThatZone() {
        let app = openPicnic(deviceZone: "America/Los_Angeles")
        XCTAssertTrue(app.staticTexts["Central Time"].exists)
        XCTAssertFalse(app.staticTexts["America/Chicago"].exists)
    }

    func testAHuddlInYourOwnTimeZoneLeavesTheZoneUnsaid() {
        let app = openPicnic(deviceZone: "America/Chicago")
        XCTAssertFalse(app.staticTexts["Central Time"].exists)
        XCTAssertFalse(app.staticTexts["America/Chicago"].exists)
    }

    private func openPicnic(deviceZone: String = "America/Chicago") -> XCUIApplication {
        let routes: [[String: Any]] = [
            ["path": "/api/json/huddlz/picnic", "query": [:], "responses": [["status": 200, "body": detail]]],
            ["path": "/api/json/huddlz", "query": [:], "responses": [["status": 200, "body": "{\"data\":[\(picnic)]}"]]]
        ]
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["TZ"] = deviceZone
        app.launchEnvironment["HUDDLZ_UI_SESSION_ID"] = UUID().uuidString
        app.launchEnvironment["HUDDLZ_UI_HTTP_SCRIPT"] = String(decoding: try! JSONSerialization.data(withJSONObject: routes), as: UTF8.self)
        app.launchEnvironment["HUDDLZ_UI_MAP_SCRIPT"] = "[]"
        app.launch()
        XCTAssertTrue(app.buttons["huddl-picnic"].waitForExistence(timeout: 10))
        app.buttons["huddl-picnic"].tap()
        XCTAssertTrue(app.staticTexts["Saturday, September 12"].waitForExistence(timeout: 10))
        return app
    }

    private let about = """
        Bring a blanket and something to share. We'll set up by the big oak near the pond.

        Games start around noon: frisbee, cards, and a slow walk around the lake for anyone who wants one. Kids and dogs are welcome.

        If it rains we move to the pavilion. Look for the green flag.

        We'll bring lemonade, plates, and a first-aid kit. If you can, bring a dish that doesn't need a fridge; fruit, bread, and cookies always go fast.

        New to the group? Say hi to whoever is holding the clipboard and we'll introduce you around. Nobody needs to stay the whole afternoon.

        Street parking fills up fast, so try the garage on Oak Street.
        """

    private var picnic: String {
        let text = String(decoding: try! JSONSerialization.data(withJSONObject: [about]), as: UTF8.self).dropFirst().dropLast()
        return #"{"type":"huddl","id":"picnic","attributes":{"title":"Picnic in the park","description":\#(text),"starts_at":"2099-09-12T16:00:00Z","ends_at":"2099-09-12T19:00:00Z","time_zone":"America/Chicago","event_type":"virtual","lifecycle_state":"published"},"relationships":{"group":{"data":{"type":"group","id":"neighbors"}}}}"#
    }

    private var detail: String {
        #"{"data":\#(picnic),"included":[{"type":"group","id":"neighbors","attributes":{"name":"Juniper Neighbors","slug":"juniper-neighbors"}}]}"#
    }
}
