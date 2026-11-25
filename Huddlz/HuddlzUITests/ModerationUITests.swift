import XCTest

/// Reporting and blocking from the huddl and group pages, and unblocking from the account.
@MainActor
final class ModerationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testBlockingAnOrganizerRemovesTheirHuddlFromDiscovery() {
        let app = makeApp(searchResponses: [page([event]), page([])])
        app.launchWithSavedSession()
        openHuddl(app)
        XCTAssertTrue(app.buttons["More options"].waitForExistence(timeout: 5))
        app.buttons["More options"].tap()
        app.buttons["Block organizer"].tap()
        XCTAssertTrue(app.staticTexts["Block this organizer?"].waitForExistence(timeout: 5))
        app.buttons["Block organizer"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Organizer blocked"].waitForExistence(timeout: 10))
        app.buttons["OK"].tap()
        // Blocking leaves the huddl page, and Discover drops the organizer's huddl.
        XCTAssertTrue(app.staticTexts["Find your people."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForNonExistence(timeout: 10))
    }

    func testReportingThenBlockingAGroupThatHasNoUpcomingHuddlz() {
        let app = makeApp()
        app.launchWithSavedSession()
        XCTAssertTrue(app.tabBars.buttons["Agenda"].waitForExistence(timeout: 60))
        // While Discover is selected the other tabs fold into one pill; Agenda opens them.
        app.tabBars.buttons["Agenda"].tap()
        XCTAssertTrue(app.tabBars.buttons["Groups"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Groups"].tap()
        XCTAssertTrue(app.buttons["group-neighbors"].waitForExistence(timeout: 10))
        app.buttons["group-neighbors"].tap()
        XCTAssertTrue(app.staticTexts["No upcoming huddlz"].waitForExistence(timeout: 10))

        XCTAssertTrue(app.buttons["More options"].waitForExistence(timeout: 5))
        app.buttons["More options"].tap()
        app.buttons["Report group"].tap()
        XCTAssertTrue(app.staticTexts["Report this group?"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Report group"].isEnabled)
        app.buttons["report-reason-spam"].tap()
        app.buttons["Report group"].tap()
        XCTAssertTrue(app.staticTexts["Thanks—we’ve received your report."].waitForExistence(timeout: 10))
        app.buttons["OK"].tap()
        XCTAssertTrue(app.staticTexts["No upcoming huddlz"].waitForExistence(timeout: 5))

        app.buttons["More options"].tap()
        app.buttons["Block group owner"].tap()
        XCTAssertTrue(app.staticTexts["Block this group’s owner?"].waitForExistence(timeout: 5))
        app.buttons["Block group owner"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Group owner blocked"].waitForExistence(timeout: 10))
        app.buttons["OK"].tap()
        // Blocking leaves the group page for the list the person came from.
        XCTAssertTrue(app.staticTexts["Your groups"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No upcoming huddlz"].waitForNonExistence(timeout: 5))
    }

    func testUnblockingFromTheAccountBringsTheirHuddlzBack() {
        let app = makeApp(searchResponses: [page([]), page([event])],
                          blockResponses: [blocks(["Crypto Kings Promo"])])
        app.launchWithSavedSession()
        XCTAssertTrue(app.buttons["Account"].waitForExistence(timeout: 60))
        app.buttons["Account"].tap()
        XCTAssertTrue(app.buttons["Blocked people"].waitForExistence(timeout: 10))
        // The account sheet opens tall enough to reach everything below the new row.
        XCTAssertTrue(app.buttons["Sign out"].isHittable)
        XCTAssertTrue(app.buttons["Code of Conduct"].isHittable)
        app.buttons["Blocked people"].tap()
        XCTAssertTrue(app.staticTexts["Crypto Kings Promo"].waitForExistence(timeout: 10))
        app.buttons["Unblock Crypto Kings Promo"].tap()
        XCTAssertTrue(app.staticTexts["Crypto Kings Promo"].waitForNonExistence(timeout: 10))
        app.buttons["Close blocked people"].tap()
        app.buttons["Close account"].tap()
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 10))
    }

    func testVisitorsSignInBeforeReportingOrBlocking() {
        let app = makeApp()
        app.launch()
        openHuddl(app)
        XCTAssertTrue(app.buttons["More options"].waitForExistence(timeout: 5))
        app.buttons["More options"].tap()
        XCTAssertFalse(app.buttons["Block organizer"].exists)
        app.buttons["Sign in to report or block"].tap()
        app.textFields["Email"].typeAfterFocusing("neighbor@example.com")
        app.secureTextFields["Password"].typeAfterFocusing("sample-password\n")
        XCTAssertTrue(app.buttons["Close account"].waitForNonExistence(timeout: 60))
        // Signed in, the same menu now offers both once ownership is checked.
        XCTAssertTrue(app.buttons["More options"].waitForExistence(timeout: 5))
        app.buttons["More options"].tap()
        XCTAssertTrue(app.buttons["Report organizer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Block organizer"].exists)
    }

    private func makeApp(searchResponses: [[String: Any]]? = nil, blockResponses: [[String: Any]]? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HUDDLZ_UI_SESSION_ID"] = UUID().uuidString
        app.launchEnvironment["HUDDLZ_UI_MAP_SCRIPT"] = "[]"
        let user = #"{"id":"neighbor","email":"neighbor@example.com","display_name":"Our Neighbor"}"#
        let block = #"{"data":{"type":"user_block","id":"b1","attributes":{"blocked_user_name":"Crypto Kings Promo"}}}"#
        let routes: [[String: Any]] = [
            route("/api/auth/sign_in", body: "{\"token\":\"fixture-token\",\"user\":\(user)}"),
            route("/api/auth/me", body: "{\"user\":\(user)}"),
            ["path": "/api/json/profile", "query": [:], "responses": [["status": 503, "body": "{}"]]],
            route("/api/json/huddlz", query: ["fields[huddl]": "attendance_state"],
                  body: #"{"data":[{"id":"coffee","attributes":{"attendance_state":"none"}}]}"#),
            ["path": "/api/json/huddlz", "query": [:], "responses": searchResponses ?? [page([event])]],
            route("/api/json/huddlz/coffee", query: ["fields[huddl]": "attendance_state"],
                  body: #"{"data":{"id":"coffee","attributes":{"attendance_state":"none"}}}"#),
            route("/api/json/huddlz/coffee", query: ["fields[huddl]": "organized_by_me"],
                  body: #"{"data":{"id":"coffee","attributes":{"organized_by_me":false}}}"#),
            route("/api/json/huddlz/coffee", body: "{\"data\":\(event)}"),
            route("/api/json/groups/mine", body: "{\"data\":[\(group)],\"links\":{\"next\":null}}"),
            route("/api/json/groups/neighbors", query: ["fields[group]": "owned_by_me"],
                  body: #"{"data":{"id":"neighbors","attributes":{"owned_by_me":false}}}"#),
            route("/api/json/groups/neighbors", body: "{\"data\":\(group)}"),
            route("/api/json/huddlz/by_group", body: #"{"data":[]}"#),
            ["path": "/api/json/account_reports/organizer", "query": [:], "responses": [["status": 201, "body": ""]]],
            ["path": "/api/json/account_reports/group", "query": [:], "responses": [["status": 201, "body": ""]]],
            ["path": "/api/json/blocks/organizer", "query": [:], "responses": [["status": 201, "body": block]]],
            ["path": "/api/json/blocks/group", "query": [:], "responses": [["status": 201, "body": block]]],
            ["path": "/api/json/blocks/b1", "query": [:], "responses": [["status": 200, "body": #"{"data":null}"#]]],
            ["path": "/api/json/blocks", "query": [:], "responses": (blockResponses ?? []) + [blocks([])]]
        ]
        app.launchEnvironment["HUDDLZ_UI_HTTP_SCRIPT"] = String(decoding: try! JSONSerialization.data(withJSONObject: routes), as: UTF8.self)
        return app
    }

    private func openHuddl(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 60))
        app.buttons["huddl-coffee"].tap()
        XCTAssertTrue(app.staticTexts["Bring a mug."].waitForExistence(timeout: 5))
    }

    private func page(_ events: [String]) -> [String: Any] {
        ["status": 200, "body": "{\"data\":[\(events.joined(separator: ","))]}"]
    }

    private func blocks(_ names: [String]) -> [String: Any] {
        let data = names.enumerated().map { index, name in
            ["type": "user_block", "id": "b\(index + 1)", "attributes": ["blocked_user_name": name]]
        }
        return ["status": 200, "body": String(decoding: try! JSONSerialization.data(withJSONObject: ["data": data]), as: UTF8.self)]
    }

    private func route(_ path: String, query: [String: String] = [:], body: String) -> [String: Any] {
        ["path": path, "query": query, "responses": [["status": 200, "body": body]]]
    }

    private let event = #"{"type":"huddl","id":"coffee","attributes":{"title":"Coffee with neighbors","description":"Bring a mug.","starts_at":"2099-09-10T13:00:00Z","ends_at":"2099-09-10T14:00:00Z","time_zone":"America/Chicago","event_type":"in_person","lifecycle_state":"published"}}"#
    private let group = #"{"type":"group","id":"neighbors","attributes":{"name":"Juniper Neighbors","description":"Neighbors who love getting outside.","location":"Austin, TX"}}"#
}
