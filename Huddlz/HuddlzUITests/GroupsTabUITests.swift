import XCTest

/// The Groups tab lists the signed-in member's groups and opens each group's page.
@MainActor
final class GroupsTabUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testGroupsListMembershipsAndOpenTheGroupWithItsHuddlz() {
        let app = launch(groupsResponses: [["status": 200, "body": page([neighbors, runners])]])
        openGroups(app)
        XCTAssertTrue(app.buttons["group-neighbors"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["group-neighbors"].label.contains("Juniper Neighbors"))
        XCTAssertTrue(app.buttons["group-neighbors"].label.contains("Austin, TX"))
        XCTAssertTrue(app.buttons["group-runners"].label.contains("River Runners"))
        XCTAssertFalse(app.buttons["Load more groups"].exists)

        app.buttons["group-neighbors"].tap()
        XCTAssertTrue(app.staticTexts["Neighbors who love getting outside."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["group-runners"].waitForExistence(timeout: 5))
    }

    func testGroupsHeaderOpensTheAccountSheet() {
        let app = launch(groupsResponses: [["status": 200, "body": page([neighbors])]])
        openGroups(app)
        XCTAssertTrue(app.buttons["group-neighbors"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["The people you keep showing up for."].exists)
        app.buttons["Account"].tap()
        XCTAssertTrue(app.staticTexts["Our Neighbor"].waitForExistence(timeout: 5))
    }

    func testNoGroupsExplainsHowToJoinOne() {
        let app = launch(groupsResponses: [["status": 200, "body": page([])]])
        openGroups(app)
        XCTAssertTrue(app.staticTexts["No groups yet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Open a huddl and visit its group to join."].exists)
        XCTAssertFalse(app.buttons["Sign in"].exists)
    }

    func testFailedGroupsLoadOffersRetry() {
        let app = launch(groupsResponses: [["status": 503, "body": "{}"],
                                           ["status": 200, "body": page([neighbors])]])
        openGroups(app)
        XCTAssertTrue(app.staticTexts["Couldn’t load your groups"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["group-neighbors"].exists)
        app.buttons["Try loading groups again"].tap()
        XCTAssertTrue(app.buttons["group-neighbors"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Couldn’t load your groups"].exists)
    }

    func testLoadingMoreGroupsAddsTheNextPage() {
        let next = "https://huddlz.com/api/json/groups/mine?page%5Blimit%5D=20&page%5Boffset%5D=20"
        let app = launch(groupsResponses: [["status": 200, "body": page([neighbors], next: next)]],
                         extraRoutes: [["path": "/api/json/groups/mine", "query": ["page[offset]": "20"],
                                        "responses": [["status": 200, "body": page([runners])]]]])
        openGroups(app)
        XCTAssertTrue(app.buttons["group-neighbors"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["group-runners"].exists)
        app.buttons["Load more groups"].tap()
        XCTAssertTrue(app.buttons["group-runners"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["group-neighbors"].exists)
        XCTAssertFalse(app.buttons["Load more groups"].exists)
    }

    func testSigningOutClearsGroupsUntilSigningInAgain() {
        let app = launch(groupsResponses: [["status": 200, "body": page([neighbors])],
                                           ["status": 200, "body": page([runners])]])
        openGroups(app)
        XCTAssertTrue(app.buttons["group-neighbors"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Discover"].tap()
        XCTAssertTrue(app.buttons["Account"].waitForExistence(timeout: 5))
        app.buttons["Account"].tap()
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 5))
        app.buttons["Sign out"].tap()
        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 5))
        app.buttons["Close account"].tap()

        app.tabBars.buttons["Groups"].tap()
        XCTAssertTrue(app.staticTexts["Sign in to see your groups"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["group-neighbors"].exists)

        app.buttons["Sign in"].tap()
        app.textFields["Email"].tap()
        app.textFields["Email"].typeText("neighbor@example.com")
        app.secureTextFields["Password"].tap()
        app.secureTextFields["Password"].typeText("sample-password\n")
        XCTAssertTrue(app.buttons["group-runners"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["group-neighbors"].exists)
    }

    private func openGroups(_ app: XCUIApplication) {
        // While Discover is selected the other tabs fold into one pill; Agenda opens them.
        XCTAssertTrue(app.tabBars.buttons["Agenda"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Agenda"].tap()
        XCTAssertTrue(app.tabBars.buttons["Groups"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Groups"].tap()
    }

    private func launch(groupsResponses: [[String: Any]], extraRoutes: [[String: Any]] = []) -> XCUIApplication {
        let user = #"{"id":"neighbor","email":"neighbor@example.com","display_name":"Our Neighbor"}"#
        let group = #"{"data":{"type":"group","id":"neighbors","attributes":{"name":"Juniper Neighbors","description":"Neighbors who love getting outside.","location":"Austin, TX"}}}"#
        let routes: [[String: Any]] = extraRoutes + [
            ["path": "/api/json/groups/mine", "query": ["page[limit]": "20"], "responses": groupsResponses],
            ["path": "/api/json/groups/neighbors", "query": [:], "responses": [["status": 200, "body": group]]],
            ["path": "/api/json/huddlz/by_group", "query": ["group_id": "neighbors"],
             "responses": [["status": 200, "body": "{\"data\":[\(coffee)]}"]]],
            ["path": "/api/json/huddlz", "query": [:], "responses": [["status": 200, "body": "{\"data\":[]}"]]],
            ["path": "/api/auth/me", "query": [:], "responses": [["status": 200, "body": "{\"user\":\(user)}"]]],
            ["path": "/api/auth/sign_out", "query": [:], "responses": [["status": 204, "body": ""]]],
            ["path": "/api/auth/sign_in", "query": [:],
             "responses": [["status": 200, "body": "{\"token\":\"fixture-token\",\"user\":\(user)}"]]],
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

    private func page(_ groups: [String], next: String? = nil) -> String {
        let link = next.map { "\"\($0)\"" } ?? "null"
        return "{\"data\":[\(groups.joined(separator: ","))],\"links\":{\"next\":\(link)}}"
    }

    private let neighbors = #"{"type":"group","id":"neighbors","attributes":{"name":"Juniper Neighbors","location":"Austin, TX","time_zone":"America/Chicago","is_public":true,"slug":"juniper-neighbors","latitude":30.27,"longitude":-97.74}}"#
    private let runners = #"{"type":"group","id":"runners","attributes":{"name":"River Runners","location":"Portland, OR","time_zone":"America/Los_Angeles","is_public":true,"slug":"river-runners","latitude":45.52,"longitude":-122.68}}"#
    private let coffee = #"{"type":"huddl","id":"coffee","attributes":{"title":"Coffee with neighbors","description":"Bring a mug.","starts_at":"2026-09-10T13:00:00Z","ends_at":"2026-09-10T14:00:00Z","time_zone":"America/Chicago","event_type":"virtual","lifecycle_state":"published"}}"#
}
