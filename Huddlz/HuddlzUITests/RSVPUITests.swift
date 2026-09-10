import XCTest

@MainActor
final class RSVPUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testRSVPAndCancellationUpdateYourAttendance() {
        let app = makeApp(status: "none")
        var delayed = response("confirmed")
        delayed["delaySeconds"] = 5
        setRoutes(app, status: "none", rsvpResponses: [delayed], joiningResponses: [linkResponse(nil), linkResponse("https://example.com/room"), linkResponse(nil)])
        app.launch()
        signIn(app)
        openHuddl(app)
        XCTAssertTrue(app.buttons["RSVP"].waitForExistence(timeout: 10))
        app.buttons["RSVP"].tap()
        XCTAssertFalse(app.buttons["RSVP"].isEnabled)
        XCTAssertTrue(app.staticTexts["You haven’t RSVP’d"].exists)
        XCTAssertTrue(app.staticTexts["You’re going"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Join online"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "RSVP confirmed"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Cancel RSVP"].tap()
        XCTAssertTrue(app.staticTexts["You haven’t RSVP’d"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["RSVP"].exists)
        XCTAssertTrue(app.buttons["Join online"].waitForNonExistence(timeout: 10))
        signOut(app)
    }

    func testSignInReturnsToTheHuddlToFinishRSVP() {
        let app = makeApp(status: "none")
        app.launch()
        openHuddl(app)
        XCTAssertTrue(app.buttons["Sign in to RSVP"].waitForExistence(timeout: 5))
        app.buttons["Sign in to RSVP"].tap()
        app.textFields["Email"].tap()
        app.textFields["Email"].typeText("neighbor@example.com")
        app.secureTextFields["Password"].tap()
        app.secureTextFields["Password"].typeText("sample-password\n")
        XCTAssertTrue(app.buttons["RSVP"].waitForExistence(timeout: 60))
        XCTAssertTrue(app.staticTexts["Bring a mug."].exists)
        XCTAssertFalse(app.staticTexts["You’re going"].exists)
        app.buttons["RSVP"].tap()
        XCTAssertTrue(app.staticTexts["You’re going"].waitForExistence(timeout: 10))
        signOut(app)
    }

    func testRejectedRSVPKeepsStatusAndAllowsRetry() {
        let app = makeApp(status: "none")
        setRoutes(app, status: "none", rsvpResponses: [
            ["status": 503, "body": "{}"],
            ["status": 422, "body": #"{"errors":[{"detail":"This huddl is full"}]}"#],
            response("confirmed")
        ])
        app.launch()
        signIn(app)
        openHuddl(app)
        XCTAssertTrue(app.buttons["RSVP"].waitForExistence(timeout: 10))
        app.buttons["RSVP"].tap()
        XCTAssertTrue(app.staticTexts["Couldn’t update your RSVP. Please try again."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["You haven’t RSVP’d"].exists)
        app.buttons["RSVP"].tap()
        XCTAssertTrue(app.staticTexts["This huddl is full"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Bring a mug."].exists)
        app.buttons["RSVP"].tap()
        XCTAssertTrue(app.staticTexts["You’re going"].waitForExistence(timeout: 10))
        signOut(app)
    }

    func testClosedHuddlzExplainWhyRSVPIsUnavailable() {
        for (state, year) in [("cancelled", "2099"), ("completed", "2099"), ("draft", "2099"), ("published", "2020")] {
            let app = makeApp(status: "none")
            setRoutes(app, status: "none", lifecycle: state, year: year)
            app.launch()
            openHuddl(app)
            XCTAssertTrue(app.staticTexts["RSVPs are closed for this huddl."].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["Sign in to RSVP"].exists)
            XCTAssertFalse(app.buttons["RSVP"].exists)
            app.terminate()
        }
    }

    func testRSVPRefreshesJoiningAccessAndSearchBadge() {
        let app = makeApp(status: "none")
        setRoutes(app, status: "none", joiningResponses: [linkResponse(nil), linkResponse("https://example.com/room")])
        app.launch()
        signIn(app)
        openHuddl(app)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Online joining details aren’t available for this account yet."].waitForExistence(timeout: 10))
        app.swipeDown()
        app.buttons["RSVP"].tap()
        XCTAssertTrue(app.staticTexts["You’re going"].waitForExistence(timeout: 10))
        app.swipeUp()
        XCTAssertTrue(app.buttons["Join online"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()
        let card = app.buttons["huddl-coffee"]
        let badge = NSPredicate(format: "label CONTAINS %@", "Going")
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: badge, object: card)], timeout: 10) == .completed)
        card.tap()
        signOut(app)
    }

    private func linkResponse(_ value: String?) -> [String: Any] {
        let body: [String: Any] = ["data": ["id": "coffee", "attributes": ["visible_virtual_link": value as Any? ?? NSNull()]]]
        return ["status": 200, "body": String(decoding: try! JSONSerialization.data(withJSONObject: body), as: UTF8.self)]
    }

    func testWaitlistedPersonCanLeaveTheWaitlist() {
        let app = makeApp(status: "waitlisted")
        app.launch()
        signIn(app)
        openHuddl(app)
        XCTAssertTrue(app.buttons["Leave waitlist"].waitForExistence(timeout: 10))
        app.buttons["Leave waitlist"].tap()
        XCTAssertTrue(app.staticTexts["You haven’t RSVP’d"].waitForExistence(timeout: 10))
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

    private func setRoutes(_ app: XCUIApplication, status: String, attendanceResponses: [[String: Any]]? = nil, rsvpResponses: [[String: Any]]? = nil, lifecycle: String = "published", year: String = "2099", joiningResponses: [[String: Any]]? = nil) {
        let event = self.event.replacingOccurrences(of: "published", with: lifecycle).replacingOccurrences(of: "2099", with: year)
        let user = #"{"id":"neighbor","email":"neighbor@example.com","display_name":"Our Neighbor"}"#
        let routes: [[String: Any]] = [
            route("/api/auth/sign_in", body: "{\"token\":\"fixture-token\",\"user\":\(user)}"),
            route("/api/auth/me", body: "{\"user\":\(user)}"),
            route("/api/auth/sign_out", body: "{}"),
            route("/api/json/profile", body: #"{"id":"neighbor","search_defaults":{"home_location":null,"distance_miles":25}}"#),
            ["path": "/api/json/huddlz", "query": ["fields[huddl]": "attendance_state"], "responses": [
                ["status": 200, "body": "{\"data\":[{\"id\":\"coffee\",\"attributes\":{\"attendance_state\":\"none\"}}]}"],
                ["status": 200, "body": "{\"data\":[{\"id\":\"coffee\",\"attributes\":{\"attendance_state\":\"confirmed\"}}]}"]]],
            ["path": "/api/json/huddlz/coffee", "query": ["fields[huddl]": "visible_virtual_link"], "responses": joiningResponses ?? [linkResponse(nil)]],
            route("/api/json/huddlz", body: "{\"data\":[\(event)]}"),
            ["path": "/api/json/huddlz/coffee", "query": ["fields[huddl]": "attendance_state"],
             "responses": attendanceResponses ?? [response(status)]],
            ["path": "/api/json/huddlz/coffee/rsvp", "query": [:], "responses": rsvpResponses ?? [response("confirmed")]],
            route("/api/json/huddlz/coffee/cancel_rsvp", body: "{\"data\":{\"id\":\"coffee\",\"attributes\":{\"attendance_state\":\"none\"}}}"),
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
    private let event = #"{"type":"huddl","id":"coffee","attributes":{"title":"Coffee with neighbors","description":"Bring a mug.","starts_at":"2099-09-10T13:00:00Z","ends_at":"2099-09-10T14:00:00Z","time_zone":"America/Chicago","event_type":"virtual","lifecycle_state":"published"}}"#
}
