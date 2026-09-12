import XCTest

/// The Agenda tab lists the signed-in member's upcoming RSVPs by day and opens each huddl.
@MainActor
final class AgendaTabUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testAgendaListsUpcomingRSVPsByDayAndOpensTheHuddl() {
        let app = launch(agendaResponses: [["status": 200, "body": page([hike, coffee])]])
        openAgenda(app)
        let coffeeRow = app.buttons["agenda-coffee"]
        let hikeRow = app.buttons["agenda-hike"]
        XCTAssertTrue(coffeeRow.waitForExistence(timeout: 5))
        XCTAssertTrue(coffeeRow.label.contains("Coffee with neighbors"))
        XCTAssertTrue(coffeeRow.label.contains("Going"))
        XCTAssertTrue(coffeeRow.label.contains("9:00"))
        XCTAssertTrue(hikeRow.label.contains("Riverside hike"))
        XCTAssertTrue(hikeRow.label.contains("Waitlisted"))
        XCTAssertTrue(app.staticTexts["Monday, September 14"].exists)
        XCTAssertTrue(app.staticTexts["Tuesday, September 15"].exists)
        XCTAssertTrue(app.staticTexts["Two huddlz coming up."].exists)
        // Soonest first, whatever order the API used.
        XCTAssertLessThan(coffeeRow.frame.minY, hikeRow.frame.minY)

        coffeeRow.tap()
        XCTAssertTrue(app.staticTexts["Bring a mug and meet your neighbors."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["You’re going"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(hikeRow.waitForExistence(timeout: 5))
    }

    func testAgendaHeaderOpensTheAccountSheet() {
        let app = launch(agendaResponses: [["status": 200, "body": page([coffee])]])
        openAgenda(app)
        XCTAssertTrue(app.buttons["agenda-coffee"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["One huddl coming up."].exists)
        app.buttons["Account"].tap()
        XCTAssertTrue(app.staticTexts["Our Neighbor"].waitForExistence(timeout: 5))
    }

    func testEmptyAgendaPointsToDiscover() {
        let app = launch(agendaResponses: [["status": 200, "body": page([])]])
        openAgenda(app)
        XCTAssertTrue(app.staticTexts["Nothing on your agenda"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your RSVPs and waitlists, by date."].exists)
        XCTAssertTrue(app.staticTexts["RSVP to a huddl in Discover and it will show up here."].exists)
        XCTAssertFalse(app.buttons["Sign in"].exists)
    }

    func testFailedAgendaLoadOffersRetry() {
        let app = launch(agendaResponses: [["status": 503, "body": "{}"],
                                           ["status": 200, "body": page([coffee])]])
        openAgenda(app)
        XCTAssertTrue(app.staticTexts["Couldn’t load your agenda"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["agenda-coffee"].exists)
        app.buttons["Try loading your agenda again"].tap()
        XCTAssertTrue(app.buttons["agenda-coffee"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Couldn’t load your agenda"].exists)
    }

    func testCancellingAnRSVPRemovesItFromTheAgenda() {
        let app = launch(agendaResponses: [["status": 200, "body": page([coffee])],
                                           ["status": 200, "body": page([])]])
        openAgenda(app)
        XCTAssertTrue(app.buttons["agenda-coffee"].waitForExistence(timeout: 5))
        app.buttons["agenda-coffee"].tap()
        XCTAssertTrue(app.buttons["Cancel RSVP"].waitForExistence(timeout: 5))
        app.buttons["Cancel RSVP"].tap()
        XCTAssertTrue(app.staticTexts["You haven’t RSVP’d"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Nothing on your agenda"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["agenda-coffee"].exists)
    }

    private func openAgenda(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["Agenda"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Agenda"].tap()
    }

    private func launch(agendaResponses: [[String: Any]]) -> XCUIApplication {
        let user = #"{"id":"neighbor","email":"neighbor@example.com","display_name":"Our Neighbor"}"#
        let routes: [[String: Any]] = [
            ["path": "/api/json/huddlz/upcoming", "query": ["filter[attendance_state][in][]": "confirmed"], "responses": agendaResponses],
            ["path": "/api/json/huddlz/coffee", "query": ["fields[huddl]": "attendance_state"],
             "responses": [["status": 200, "body": attendance("confirmed")], ["status": 200, "body": attendance("none")]]],
            ["path": "/api/json/huddlz/coffee/cancel_rsvp", "query": [:], "responses": [["status": 200, "body": attendance("none")]]],
            ["path": "/api/json/huddlz/coffee", "query": [:], "responses": [["status": 200, "body": "{\"data\":\(coffee)}"]]],
            ["path": "/api/json/huddlz", "query": [:], "responses": [["status": 200, "body": "{\"data\":[]}"]]],
            ["path": "/api/auth/me", "query": [:], "responses": [["status": 200, "body": "{\"user\":\(user)}"]]],
            ["path": "/api/json/profile", "query": [:], "responses": [["status": 503, "body": "{}"]]]
        ]
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HUDDLZ_UI_SESSION_ID"] = UUID().uuidString
        app.launchEnvironment["HUDDLZ_UI_HTTP_SCRIPT"] = String(decoding: try! JSONSerialization.data(withJSONObject: routes), as: UTF8.self)
        app.launchEnvironment["HUDDLZ_UI_MAP_SCRIPT"] = "[]"
        app.launchWithSavedSession()
        return app
    }

    private func attendance(_ state: String) -> String {
        "{\"data\":{\"id\":\"coffee\",\"attributes\":{\"attendance_state\":\"\(state)\"}}}"
    }

    private func page(_ events: [String]) -> String { "{\"data\":[\(events.joined(separator: ","))]}" }

    private var coffee: String {
        """
        {"type":"huddl","id":"coffee","attributes":{
          "title":"Coffee with neighbors","description":"Bring a mug and meet your neighbors.",
          "starts_at":"2099-09-14T13:00:00Z","ends_at":"2099-09-14T15:00:00Z",
          "time_zone":"America/New_York","event_type":"in_person",
          "physical_location":"Juniper Café","thumbnail_url":null,"lifecycle_state":"published",
          "attendance_state":"confirmed"
        }}
        """
    }

    private var hike: String {
        """
        {"type":"huddl","id":"hike","attributes":{
          "title":"Riverside hike","description":"Bring water.",
          "starts_at":"2099-09-15T23:00:00Z","ends_at":"2099-09-16T01:00:00Z",
          "time_zone":"America/New_York","event_type":"in_person",
          "physical_location":"Riverside Park","thumbnail_url":null,"lifecycle_state":"published",
          "attendance_state":"waitlisted"
        }}
        """
    }
}
