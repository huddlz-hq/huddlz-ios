import XCTest

@MainActor
final class SearchBadgeUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testSearchCardsMarkGoingAndWaitlistedButLeaveOtherCardsUnmarked() {
        let app = launch()
        signIn(app)
        let coffee = app.buttons["huddl-coffee"]
        XCTAssertTrue(coffee.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForBadge("Going", on: coffee))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Search RSVP badge"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let walk = app.buttons["huddl-walk"]
        reveal(walk, in: app)
        XCTAssertTrue(waitForBadge("Waitlisted", on: walk))
        let picnic = app.buttons["huddl-picnic"]
        reveal(picnic, in: app)
        XCTAssertFalse(picnic.label.contains("Going"))
        XCTAssertFalse(picnic.label.contains("Waitlisted"))
        signOut(app)
    }

    func testReturningRefreshesBadgesAndSigningOutRemovesThem() {
        let changed = #"{"data":[{"id":"coffee","attributes":{"attendance_state":"waitlisted"}}]}"#
        let app = launch(stateResponses: [["status": 200, "body": states], ["status": 200, "body": changed]])
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["huddl-coffee"].label.contains("Going"))
        signIn(app)
        XCTAssertTrue(waitForBadge("Going", on: app.buttons["huddl-coffee"]))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(waitForBadge("Waitlisted", on: app.buttons["huddl-coffee"]))
        XCTAssertFalse(app.buttons["huddl-coffee"].label.contains("Going"))
        signOut(app)
        app.buttons["Close account"].tap()
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["huddl-coffee"].label.contains("Going"))
        XCTAssertFalse(app.buttons["huddl-coffee"].label.contains("Waitlisted"))
    }

    func testPullToRefreshUpdatesBadgesWithoutRemovingCards() {
        let changed = #"{"data":[{"id":"coffee","attributes":{"attendance_state":"waitlisted"}}]}"#
        let app = launch(stateResponses: [["status": 200, "body": states], ["status": 200, "body": changed]])
        signIn(app)
        XCTAssertTrue(waitForBadge("Going", on: app.buttons["huddl-coffee"]))
        let scroll = app.scrollViews.firstMatch
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            .press(forDuration: 0.1, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        XCTAssertTrue(app.buttons["huddl-coffee"].exists)
        XCTAssertTrue(waitForBadge("Waitlisted", on: app.buttons["huddl-coffee"]))
        signOut(app)
    }

    private func waitForBadge(_ badge: String, on card: XCUIElement) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", badge), object: card)], timeout: 10) == .completed
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    private func launch(stateResponses: [[String: Any]]? = nil) -> XCUIApplication {
        let user = #"{"id":"neighbor","email":"neighbor@example.com","display_name":"Our Neighbor"}"#
        let events = [("coffee", "Coffee with neighbors"), ("walk", "River walk"), ("picnic", "Park picnic")]
        let page = "{\"data\":[" + events.map { event(id: $0.0, title: $0.1) }.joined(separator: ",") + "]}"

        let routes: [[String: Any]] = [
            route("/api/auth/sign_in", body: "{\"token\":\"fixture-token\",\"user\":\(user)}"),
            route("/api/auth/me", body: "{\"user\":\(user)}"),
            route("/api/auth/sign_out", body: "{}"),
            route("/api/json/profile", body: #"{"id":"neighbor","search_defaults":{"home_location":null,"distance_miles":25}}"#),
            ["path": "/api/json/huddlz", "query": ["fields[huddl]": "attendance_state"],
             "responses": stateResponses ?? [["status": 200, "body": states]]],
            route("/api/json/huddlz", body: page)
        ]
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HUDDLZ_UI_SESSION_ID"] = UUID().uuidString
        app.launchEnvironment["HUDDLZ_UI_HTTP_SCRIPT"] = String(decoding: try! JSONSerialization.data(withJSONObject: routes), as: UTF8.self)
        app.launch()
        return app
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

    private func signOut(_ app: XCUIApplication) {
        for _ in 0..<5 where !app.buttons["Account"].isHittable { app.swipeDown() }
        app.buttons["Account"].tap()
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 60))
        app.buttons["Sign out"].tap()
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 60))
    }

    private func route(_ path: String, query: [String: String] = [:], body: String) -> [String: Any] {
        ["path": path, "query": query, "responses": [["status": 200, "body": body]]]
    }
    private func event(id: String, title: String) -> String {
        """
        {"type":"huddl","id":"\(id)","attributes":{"title":"\(title)","starts_at":"2026-09-10T13:00:00Z","ends_at":"2026-09-10T14:00:00Z","time_zone":"America/Chicago","event_type":"virtual","lifecycle_state":"published"}}
        """
    }
    private let states = #"{"data":[{"id":"coffee","attributes":{"attendance_state":"confirmed"}},{"id":"walk","attributes":{"attendance_state":"waitlisted"}},{"id":"picnic","attributes":{"attendance_state":"none"}}]}"#
}
