import XCTest

/// The tab bar holds Agenda and Groups; Discover is the search tab.
@MainActor
final class TabsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testLaunchingShowsDiscoverWithAgendaAndGroupsTabs() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Find your people."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Agenda"].exists)
        XCTAssertTrue(app.tabBars.buttons["Groups"].exists)
        XCTAssertTrue(app.tabBars.buttons["Discover"].exists)
        XCTAssertTrue(app.tabBars.buttons["Discover"].isSelected)
    }

    func testAgendaAndGroupsAskSignedOutVisitorsToSignIn() {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["Agenda"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Agenda"].tap()
        XCTAssertTrue(app.staticTexts["Sign in to see your agenda"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Find your people."].exists)
        app.buttons["Sign in"].tap()
        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 5))
        app.buttons["Close account"].tap()

        app.tabBars.buttons["Groups"].tap()
        XCTAssertTrue(app.staticTexts["Sign in to see your groups"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Sign in to see your agenda"].exists)
        app.buttons["Sign in"].tap()
        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 5))
    }

    func testSignedInAgendaAndGroupsDoNotAskToSignIn() {
        let app = launch(savedSession: true)
        XCTAssertTrue(app.tabBars.buttons["Agenda"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Agenda"].tap()
        XCTAssertTrue(app.staticTexts["Your agenda"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Sign in"].exists)
        app.tabBars.buttons["Groups"].tap()
        XCTAssertTrue(app.staticTexts["Your groups"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Sign in"].exists)
    }

    func testReturningToDiscoverKeepsTheSearchAndFilters() {
        let app = launch()
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["huddl-hike"].exists)
        app.buttons["When: All upcoming"].tap()
        app.buttons["This week"].tap()
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("coffee\n")
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["huddl-hike"].exists)

        app.tabBars.buttons["Agenda"].tap()
        XCTAssertTrue(app.staticTexts["Sign in to see your agenda"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Discover"].tap()

        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["huddl-hike"].exists)
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "coffee")
        XCTAssertTrue(app.buttons["When: This week"].exists)
    }

    func testRotatingKeepsTheSelectedTab() {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["Groups"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Groups"].tap()
        XCTAssertTrue(app.staticTexts["Sign in to see your groups"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.staticTexts["Sign in to see your groups"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Find your people."].exists)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.staticTexts["Sign in to see your groups"].waitForExistence(timeout: 5))
    }

    func testFailedSignInFromAgendaKeepsTheFormAndEmail() {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["Agenda"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Agenda"].tap()
        app.buttons["Sign in"].tap()
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 5))
        app.textFields["Email"].tap()
        app.textFields["Email"].typeText("neighbor@example.com")
        app.secureTextFields["Password"].tap()
        app.secureTextFields["Password"].typeText("wrong-password\n")
        XCTAssertTrue(app.staticTexts["The email or password is incorrect. Try again."].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["Email"].value as? String, "neighbor@example.com")
    }

    func testReturningToDiscoverKeepsResultsWhenOffline() {
        let app = launch(discoveryResponses: [
            ["status": 200, "body": page([coffee, hike])],
            ["status": 503, "body": "{}"]
        ])
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Agenda"].tap()
        XCTAssertTrue(app.staticTexts["Sign in to see your agenda"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Discover"].tap()
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 10))
    }

    private func launch(savedSession: Bool = false, discoveryResponses: [[String: Any]]? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HUDDLZ_UI_SESSION_ID"] = UUID().uuidString
        let user = #"{"id":"user-1","display_name":"Nia Neighbor","email":"nia@example.com"}"#
        let routes: [[String: Any]] = [
            ["path": "/api/auth/sign_in", "query": [:], "responses": [["status": 401, "body": "{}", "delaySeconds": 2]]],
            ["path": "/api/json/huddlz", "query": ["query": "coffee", "date_filter": "this_week"],
             "responses": [["status": 200, "body": page([coffee])]]],
            ["path": "/api/json/huddlz", "query": [:], "responses": discoveryResponses ?? [["status": 200, "body": page([coffee, hike])]]],
            ["path": "/api/auth/me", "query": [:], "responses": [["status": 200, "body": "{\"user\":\(user)}"]]],
            ["path": "/api/json/profile", "query": [:], "responses": [["status": 200, "body": "{\"data\":{\"type\":\"profile\",\"id\":\"user-1\",\"attributes\":{}}}"]]]
        ]
        app.launchEnvironment["HUDDLZ_UI_HTTP_SCRIPT"] = String(decoding: try! JSONSerialization.data(withJSONObject: routes), as: UTF8.self)
        if savedSession { app.launchWithSavedSession() } else { app.launch() }
        return app
    }

    private func page(_ events: [String]) -> String {
        "{\"data\":[\(events.joined(separator: ","))],\"links\":{\"next\":null}}"
    }

    private var coffee: String {
        """
        {"type":"huddl","id":"coffee","attributes":{
          "title":"Coffee with neighbors","description":"Bring a mug and meet your neighbors.",
          "starts_at":"2026-09-10T13:00:00Z","ends_at":"2026-09-10T16:00:00Z",
          "time_zone":"America/New_York","event_type":"in_person",
          "physical_location":"Juniper Café","thumbnail_url":null,"lifecycle_state":"published"
        }}
        """
    }

    private var hike: String {
        coffee.replacingOccurrences(of: "coffee", with: "hike").replacingOccurrences(of: "Coffee with neighbors", with: "Riverside hike")
    }
}
