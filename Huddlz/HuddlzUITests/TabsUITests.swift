import XCTest

/// The tab bar holds Agenda and Groups; Discover is the search tab.
@MainActor
final class TabsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testLaunchingShowsDiscoverWithItsSearchFieldAndACollapsedTabPill() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Find your people."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
        // The search tab is selected: its field is expanded and the other tabs fold into one pill.
        XCTAssertTrue(app.searchFields["Search huddlz"].exists)
        XCTAssertTrue(app.tabBars.buttons["Agenda"].exists)
        XCTAssertFalse(app.tabBars.buttons["Groups"].exists)

        app.tabBars.buttons["Agenda"].tap()
        XCTAssertTrue(app.staticTexts["Sign in to see your agenda"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Agenda"].isSelected)
        XCTAssertTrue(app.tabBars.buttons["Groups"].exists)
        XCTAssertTrue(app.tabBars.buttons["Discover"].exists)
        XCTAssertFalse(app.searchFields["Search huddlz"].exists)

        app.tabBars.buttons["Discover"].tap()
        XCTAssertTrue(app.staticTexts["Find your people."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.searchFields["Search huddlz"].waitForExistence(timeout: 5))
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
            ["path": "/api/json/huddlz/upcoming", "query": [:], "responses": [["status": 200, "body": "{\"data\":[]}"]]],
            ["path": "/api/json/groups/mine", "query": [:], "responses": [["status": 200, "body": "{\"data\":[]}"]]],
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
