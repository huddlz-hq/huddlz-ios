import XCTest

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
        app.buttons["More options"].tap()
        app.buttons["Block organizer"].tap()
        XCTAssertTrue(app.staticTexts["Block this organizer?"].waitForExistence(timeout: 5))
        app.buttons["Block organizer"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Organizer blocked"].waitForExistence(timeout: 10))
        app.buttons["OK"].tap()
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForNonExistence(timeout: 10))
    }

    func testReportingAnOrganizerNeedsAReasonAndThanksThePerson() {
        let app = makeApp()
        app.launchWithSavedSession()
        openHuddl(app)
        app.buttons["More options"].tap()
        app.buttons["Report organizer"].tap()
        XCTAssertTrue(app.staticTexts["Report the organizer?"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Report organizer"].isEnabled)
        app.buttons["report-reason-spam"].tap()
        app.textFields["What you saw, in a sentence or two."].tap()
        app.textFields["What you saw, in a sentence or two."].typeText("Coin listings")
        app.buttons["Report organizer"].tap()
        XCTAssertTrue(app.staticTexts["Thanks—we’ve received your report."].waitForExistence(timeout: 10))
        app.buttons["OK"].tap()
        XCTAssertTrue(app.staticTexts["Bring a mug."].exists)
    }

    func testUnblockingFromYourAccountBringsTheirHuddlzBack() {
        let app = makeApp(searchResponses: [page([]), page([event])],
                          blockResponses: [blocks(["Crypto Kings Promo"])])
        app.launchWithSavedSession()
        app.buttons["Account"].tap()
        XCTAssertTrue(app.staticTexts["Crypto Kings Promo"].waitForExistence(timeout: 60))
        app.buttons["Unblock Crypto Kings Promo"].tap()
        XCTAssertTrue(app.staticTexts["Crypto Kings Promo"].waitForNonExistence(timeout: 10))
        app.buttons["Close account"].tap()
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 10))
    }

    func testVisitorsSignInBeforeReportingOrBlocking() {
        let app = makeApp()
        app.launch()
        openHuddl(app)
        app.buttons["More options"].tap()
        XCTAssertFalse(app.buttons["Block organizer"].exists)
        app.buttons["Sign in to report or block"].tap()
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 5))
    }

    private func makeApp(searchResponses: [[String: Any]]? = nil, blockResponses: [[String: Any]]? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HUDDLZ_UI_SESSION_ID"] = UUID().uuidString
        let user = #"{"id":"neighbor","email":"neighbor@example.com","display_name":"Our Neighbor"}"#
        let routes: [[String: Any]] = [
            route("/api/auth/sign_in", body: "{\"token\":\"fixture-token\",\"user\":\(user)}"),
            route("/api/auth/me", body: "{\"user\":\(user)}"),
            route("/api/json/profile", body: #"{"id":"neighbor","search_defaults":{"home_location":null,"distance_miles":25}}"#),
            route("/api/json/huddlz", query: ["fields[huddl]": "attendance_state"],
                  body: #"{"data":[{"id":"coffee","attributes":{"attendance_state":"none"}}]}"#),
            ["path": "/api/json/huddlz", "query": [:], "responses": searchResponses ?? [page([event])]],
            route("/api/json/huddlz/coffee", query: ["fields[huddl]": "attendance_state"],
                  body: #"{"data":{"id":"coffee","attributes":{"attendance_state":"none"}}}"#),
            route("/api/json/huddlz/coffee", query: ["fields[huddl]": "organized_by_me"],
                  body: #"{"data":{"id":"coffee","attributes":{"organized_by_me":false}}}"#),
            route("/api/json/huddlz/coffee", body: "{\"data\":\(event)}"),
            ["path": "/api/json/account_reports/organizer", "query": [:], "responses": [["status": 201, "body": ""]]],
            ["path": "/api/json/blocks/organizer", "query": [:], "responses": [["status": 201, "body": #"{"data":{"type":"user_block","id":"b1","attributes":{}}}"#]]],
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
}
