import XCTest

@MainActor
final class GroupUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testOpeningTheHostShowsItsGroupAndReturningPreservesTheHuddl() {
        let app = launch(groupResponses: [["status": 200, "body": group]], huddlz: page([walk]))
        openHost(app)
        XCTAssertTrue(app.staticTexts["Neighbors who love getting outside."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Austin, TX"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Hosting group"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let card = app.buttons["huddl-walk"]
        for _ in 0..<3 where !card.isHittable { app.swipeUp() }
        XCTAssertTrue(card.exists)
        // The group's cards share Discover's anatomy: date stamp, type tag, weekday and start time.
        let label = card.label.replacingOccurrences(of: "\u{202F}", with: " ")
        XCTAssertTrue(label.contains("River walk"), label)
        XCTAssertTrue(label.contains("Sep 11"), label)
        XCTAssertTrue(label.contains("Fri 8:00 AM CDT"), label)
        XCTAssertTrue(label.contains("Online"), label)
        card.tap()
        XCTAssertTrue(app.staticTexts["A walk by the river."].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["huddl-walk"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Bring a mug."].waitForExistence(timeout: 5))
    }

    func testAGroupWithNoUpcomingHuddlzExplainsTheEmptyList() {
        let app = launch(groupResponses: [["status": 200, "body": group]], huddlz: page([]))
        openHost(app)
        XCTAssertTrue(app.staticTexts["No upcoming huddlz"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Neighbors who love getting outside."].exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Bring a mug."].waitForExistence(timeout: 5))
    }

    func testAnUnavailableGroupOffersRetryAndKeepsTheOriginalHuddlAccessible() {
        for status in [404, 503] {
            let app = launch(groupResponses: [["status": status, "body": "{}"], ["status": 200, "body": group]], huddlz: page([]))
            openHost(app)
            XCTAssertTrue(app.staticTexts["Couldn’t load this group"].waitForExistence(timeout: 5))
            if status == 404 {
                XCTAssertTrue(app.staticTexts["This group is no longer available."].exists)
                app.navigationBars.buttons.firstMatch.tap()
                XCTAssertTrue(app.staticTexts["Bring a mug."].waitForExistence(timeout: 5))
                continue
            }
            app.buttons["Try again"].tap()
            XCTAssertTrue(app.staticTexts["Neighbors who love getting outside."].waitForExistence(timeout: 5))
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(app.staticTexts["Bring a mug."].waitForExistence(timeout: 5))
        }
    }

    func testFailedHuddlzKeepTheGroupVisibleAndCanBeRetried() {
        let app = launch(groupResponses: [["status": 200, "body": group]], huddlz: page([walk]),
                         huddlResponses: [["status": 503, "body": "{}"], ["status": 200, "body": page([walk])]])
        openHost(app)
        XCTAssertTrue(app.staticTexts["Couldn’t load upcoming huddlz."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Neighbors who love getting outside."].exists)
        XCTAssertFalse(app.staticTexts["No upcoming huddlz"].exists)
        app.buttons["Try loading huddlz again"].tap()
        XCTAssertTrue(app.buttons["huddl-walk"].waitForExistence(timeout: 5))
    }

    func testMoreHuddlzCanBeRetriedWithoutLosingTheGroupOrExistingCards() {
        let next = "https://huddlz.com/api/json/huddlz/by_group?group_id=neighbors&page%5Bafter%5D=walk"
        let firstPage = "{\"data\":[\(walk)],\"links\":{\"next\":\"\(next)\"}}"
        let app = launch(groupResponses: [["status": 200, "body": group]], huddlz: firstPage, extraRoutes: [
            ["path": "/api/json/huddlz/by_group", "query": ["group_id": "neighbors", "page[after]": "walk"],
             "responses": [["status": 503, "body": "{}"], ["status": 200, "body": page([coffee])]]]
        ])
        openHost(app)
        let more = app.buttons["Load more huddlz"]
        for _ in 0..<4 where !more.isHittable { app.swipeUp() }
        XCTAssertTrue(more.isHittable)
        more.tap()
        let retry = app.buttons["Try loading more again"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["huddl-walk"].exists)
        retry.tap()
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
        XCTAssertFalse(more.exists)
        XCTAssertFalse(retry.exists)
    }

    private func openHost(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
        app.buttons["huddl-coffee"].tap()
        let host = app.buttons["View group: Juniper Neighbors"]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        host.tap()
    }

    private func launch(groupResponses: [[String: Any]], huddlz: String, huddlResponses: [[String: Any]]? = nil, extraRoutes: [[String: Any]] = []) -> XCUIApplication {
        let detail = """
        {"data":\(coffee.dropLast()),"relationships":{"group":{"data":{"type":"group","id":"neighbors"}}}},
        "included":[{"type":"group","id":"neighbors","attributes":{"name":"Juniper Neighbors"}}]}
        """
        let routes: [[String: Any]] = extraRoutes + [
            route("/api/json/huddlz", body: page([coffee])),
            route("/api/json/huddlz/coffee", body: detail),
            route("/api/json/huddlz/walk", body: "{\"data\":\(walk)}"),
            ["path": "/api/json/groups/neighbors", "query": [:], "responses": groupResponses],
            ["path": "/api/json/huddlz/by_group", "query": ["group_id": "neighbors", "page[limit]": "20"],
             "responses": huddlResponses ?? [["status": 200, "body": huddlz]]]
        ]
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HUDDLZ_UI_SESSION_ID"] = UUID().uuidString
        app.launchEnvironment["HUDDLZ_UI_HTTP_SCRIPT"] = String(decoding: try! JSONSerialization.data(withJSONObject: routes), as: UTF8.self)
        app.launchEnvironment["HUDDLZ_UI_MAP_SCRIPT"] = "[]"
        app.launch()
        return app
    }

    private func route(_ path: String, query: [String: String] = [:], body: String) -> [String: Any] {
        ["path": path, "query": query, "responses": [["status": 200, "body": body]]]
    }
    private func page(_ events: [String]) -> String { "{\"data\":[\(events.joined(separator: ","))]}" }
    private let group = #"{"data":{"type":"group","id":"neighbors","attributes":{"name":"Juniper Neighbors","description":"Neighbors who love getting outside.","location":"Austin, TX"}}}"#
    private let coffee = #"{"type":"huddl","id":"coffee","attributes":{"title":"Coffee with neighbors","description":"Bring a mug.","starts_at":"2026-09-10T13:00:00Z","ends_at":"2026-09-10T14:00:00Z","time_zone":"America/Chicago","event_type":"virtual","lifecycle_state":"published"}}"#
    private let walk = #"{"type":"huddl","id":"walk","attributes":{"title":"River walk","description":"A walk by the river.","starts_at":"2026-09-11T13:00:00Z","ends_at":"2026-09-11T14:00:00Z","time_zone":"America/Chicago","event_type":"virtual","lifecycle_state":"published"}}"#
}
