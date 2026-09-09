import XCTest

@MainActor
final class JoiningUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testEligibleUserCanOpenOnlineJoiningLink() {
        let app = makeApp()
        app.launch()
        signIn(app)
        openHuddl(app)
        let link = app.buttons["Join online"]
        app.swipeUp()
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 10))
        app.terminate()
        setRoutes(app, eventType: "hybrid", attendanceState: "none")
        app.launch()
        openHuddl(app)
        app.swipeUp()
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Online joining details"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        signOut(app)
        app.buttons["Close account"].tap()
        openHuddl(app)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Online joining details are shared with confirmed attendees and group organizers."].exists)
        XCTAssertFalse(link.exists)
    }

    func testReturningAfterLosingAccessRemovesJoiningLink() {
        let app = makeApp()
        setRoutes(app, joiningResponses: [response("https://example.com/huddl-room"), response(nil)])
        app.launch()
        signIn(app)
        openHuddl(app)
        app.swipeUp()
        XCTAssertTrue(app.buttons["Join online"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["Join online"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Online joining details aren’t available for this account yet."].exists)
        signOut(app)
    }

    func testFailedJoiningRequestKeepsDetailsAndCanBeRetried() {
        let app = makeApp()
        setRoutes(app, joiningResponses: [["status": 503, "body": "{}"], response("https://example.com/huddl-room")])
        app.launch()
        signIn(app)
        openHuddl(app)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Couldn’t load joining details."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Bring a mug."].exists)
        XCTAssertFalse(app.buttons["Join online"].exists)
        app.buttons["Try loading joining details again"].tap()
        XCTAssertTrue(app.buttons["Join online"].waitForExistence(timeout: 10))
        signOut(app)
    }

    func testInPersonHuddlHasNoOnlineJoiningSection() {
        let app = makeApp()
        setRoutes(app, eventType: "in_person")
        app.launch()
        openHuddl(app)
        app.swipeUp()
        XCTAssertFalse(app.staticTexts["Join online"].exists)
        XCTAssertFalse(app.buttons["Join online"].exists)
    }

    private func response(_ link: String?) -> [String: Any] {
        let attributes: [String: Any] = ["visible_virtual_link": link as Any? ?? NSNull()]
        let data = try! JSONSerialization.data(withJSONObject: ["data": ["id": "coffee", "attributes": attributes]])
        return ["status": 200, "body": String(decoding: data, as: UTF8.self)]
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HUDDLZ_UI_SESSION_ID"] = UUID().uuidString
        setRoutes(app)
        return app
    }

    private func setRoutes(_ app: XCUIApplication, eventType: String = "virtual", attendanceState: String = "confirmed", joiningResponses: [[String: Any]]? = nil) {
        let event = self.event.replacingOccurrences(of: "virtual", with: eventType)
        let user = #"{"id":"neighbor","email":"neighbor@example.com","display_name":"Our Neighbor"}"#
        let routes: [[String: Any]] = [
            route("/api/auth/sign_in", body: "{\"token\":\"fixture-token\",\"user\":\(user)}"),
            route("/api/auth/me", body: "{\"user\":\(user)}"),
            route("/api/auth/sign_out", body: "{}"),
            route("/api/json/profile", body: #"{"id":"neighbor","search_defaults":{"home_location":null,"distance_miles":25}}"#),
            route("/api/json/huddlz", body: "{\"data\":[\(event)]}"),
            ["path": "/api/json/huddlz/coffee", "query": ["fields[huddl]": "visible_virtual_link"],
             "responses": joiningResponses ?? [response("https://example.com/huddl-room")]],
            ["path": "/api/json/huddlz/coffee", "query": ["fields[huddl]": "attendance_state"], "responses": [["status": 200, "body": "{\"data\":{\"id\":\"coffee\",\"attributes\":{\"attendance_state\":\"\(attendanceState)\"}}}"]]],
            route("/api/json/huddlz/coffee", body: "{\"data\":\(event)}")
        ]
        app.launchEnvironment["HUDDLZ_UI_HTTP_SCRIPT"] = String(decoding: try! JSONSerialization.data(withJSONObject: routes), as: UTF8.self)
    }

    private func signIn(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Account"].waitForExistence(timeout: 5))
        app.buttons["Account"].tap()
        app.textFields["Email"].tap()
        app.textFields["Email"].typeText("neighbor@example.com")
        app.secureTextFields["Password"].tap()
        app.secureTextFields["Password"].typeText("sample-password\n")
        XCTAssertTrue(app.buttons["Account"].waitForExistence(timeout: 60))
    }

    private func openHuddl(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 60))
        app.buttons["huddl-coffee"].tap()
        XCTAssertTrue(app.staticTexts["Bring a mug."].waitForExistence(timeout: 5))
    }

    private func signOut(_ app: XCUIApplication) {
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Account"].tap()
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 60))
        app.buttons["Sign out"].tap()
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 60))
    }

    private func route(_ path: String, query: [String: String] = [:], body: String) -> [String: Any] {
        ["path": path, "query": query, "responses": [["status": 200, "body": body]]]
    }
    private let event = #"{"type":"huddl","id":"coffee","attributes":{"title":"Coffee with neighbors","description":"Bring a mug.","starts_at":"2026-09-10T13:00:00Z","ends_at":"2026-09-10T14:00:00Z","time_zone":"America/Chicago","event_type":"virtual","lifecycle_state":"published"}}"#
}
