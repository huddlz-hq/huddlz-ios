import XCTest

@MainActor
final class AttendanceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testDetailsShowYourCurrentRSVPAfterSigningInAndReopening() {
        let app = makeApp(status: "confirmed")
        app.launch()
        openHuddl(app)
        XCTAssertFalse(app.staticTexts["You haven’t RSVP’d"].exists)
        XCTAssertFalse(app.staticTexts["You’re going"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        signIn(app)
        openHuddl(app)
        XCTAssertTrue(app.staticTexts["You’re going"].waitForExistence(timeout: 60))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Personal RSVP status"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        for (status, message) in [("waitlisted", "You’re on the waitlist"), ("none", "You haven’t RSVP’d")] {
            app.terminate()
            setRoutes(app, status: status)
            app.launch()
            openHuddl(app)
            XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 60))
        }
        signOut(app)
    }

    func testReturningToTheAppShowsAnRSVPChangedElsewhere() {
        let app = makeApp(status: "confirmed")
        setRoutes(app, status: "confirmed", attendanceResponses: [response("confirmed"), response("none")])
        app.launchWithSavedSession()
        openHuddl(app)
        XCTAssertTrue(app.staticTexts["You’re going"].waitForExistence(timeout: 60))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["You haven’t RSVP’d"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["You’re going"].exists)
        signOut(app)
    }

    func testFailedStatusKeepsDetailsAndRetryShowsYourRSVP() {
        let app = makeApp(status: "confirmed")
        setRoutes(app, status: "confirmed", attendanceResponses: [["status": 503, "body": "{}"], response("confirmed")])
        app.launchWithSavedSession()
        openHuddl(app)
        XCTAssertTrue(app.staticTexts["Couldn’t check your RSVP."].waitForExistence(timeout: 60))
        XCTAssertTrue(app.staticTexts["Bring a mug."].exists)
        XCTAssertFalse(app.staticTexts["You haven’t RSVP’d"].exists)
        app.buttons["Try checking RSVP again"].tap()
        XCTAssertTrue(app.staticTexts["You’re going"].waitForExistence(timeout: 10))
        signOut(app)
    }

    private func response(_ state: String) -> [String: Any] {
        ["status": 200, "body": "{\"data\":{\"id\":\"coffee\",\"attributes\":{\"attendance_state\":\"\(state)\"}}}"]
    }

    private func makeApp(status: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HUDDLZ_UI_SESSION_ID"] = UUID().uuidString
        setRoutes(app, status: status)
        return app
    }

    private func setRoutes(_ app: XCUIApplication, status: String, attendanceResponses: [[String: Any]]? = nil) {
        let user = #"{"id":"neighbor","email":"neighbor@example.com","display_name":"Our Neighbor"}"#
        let routes: [[String: Any]] = [
            route("/api/auth/sign_in", body: "{\"token\":\"fixture-token\",\"user\":\(user)}"),
            route("/api/auth/me", body: "{\"user\":\(user)}"),
            route("/api/auth/sign_out", body: "{}"),
            route("/api/json/profile", body: #"{"id":"neighbor","search_defaults":{"home_location":null,"distance_miles":25}}"#),
            route("/api/json/huddlz", body: "{\"data\":[\(event)]}"),
            ["path": "/api/json/huddlz/coffee", "query": ["fields[huddl]": "attendance_state"],
             "responses": attendanceResponses ?? [response(status)]],
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
