import XCTest

@MainActor
final class AccountUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testSigningInReturnsToBrowsingAndShowsTheAccount() {
        let app = launch()
        app.buttons["When: All upcoming"].tap()
        app.buttons["This week"].tap()
        signIn(app)
        XCTAssertTrue(app.buttons["When: This week"].exists)
        app.buttons["Account"].tap()
        XCTAssertTrue(app.staticTexts["Our Neighbor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["neighbor@example.com"].exists)
        signOut(app)
    }

    func testReopeningRestoresTheSignedInAccount() {
        let app = launch()
        signIn(app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Account"].waitForExistence(timeout: 5))
        app.buttons["Account"].tap()
        XCTAssertTrue(app.staticTexts["Our Neighbor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["neighbor@example.com"].exists)
        signOut(app)
    }

    func testSigningOutStaysSignedOutAfterReopening() {
        let app = launch()
        signIn(app)
        app.buttons["Account"].tap()
        XCTAssertTrue(app.staticTexts["Our Neighbor"].waitForExistence(timeout: 5))
        signOut(app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Account"].waitForExistence(timeout: 5))
        app.buttons["Account"].tap()
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["neighbor@example.com"].exists)
    }

    func testIncorrectCredentialsKeepEmailAndAllowAnotherAttempt() {
        let app = launch(signInResponses: [
            ["status": 401, "body": "{}"],
            ["status": 200, "body": "{\"token\":\"fixture-token\",\"user\":\(user)}"]
        ])
        app.buttons["Account"].tap()
        app.textFields["Email"].tap()
        app.textFields["Email"].typeText("neighbor@example.com")
        app.secureTextFields["Password"].tap()
        app.secureTextFields["Password"].typeText("wrong-password\n")
        XCTAssertTrue(app.staticTexts["The email or password is incorrect. Try again."].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Email"].value as? String, "neighbor@example.com")
        XCTAssertFalse(app.staticTexts["Our Neighbor"].exists)
        app.secureTextFields["Password"].tap()
        app.secureTextFields["Password"].typeText("sample-password\n")
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["Done"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        app.buttons["Account"].tap()
        XCTAssertTrue(app.staticTexts["Our Neighbor"].waitForExistence(timeout: 5))
        signOut(app)
    }

    private let user = #"{"id":"neighbor","email":"neighbor@example.com","display_name":"Our Neighbor"}"#

    private func launch(signInResponses: [[String: Any]]? = nil) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HUDDLZ_UI_SESSION_ID"] = UUID().uuidString
        let routes: [[String: Any]] = [
            ["path": "/api/json/huddlz", "query": [:], "responses": [["status": 200, "body": "{\"data\":[]}"]]],
            ["path": "/api/auth/me", "query": [:], "responses": [["status": 200, "body": "{\"user\":\(user)}"]]],
            ["path": "/api/auth/sign_out", "query": [:], "responses": [["status": 204, "body": ""]]],
            ["path": "/api/auth/sign_in", "query": [:], "responses": signInResponses ?? [
                ["status": 200, "body": "{\"token\":\"fixture-token\",\"user\":\(user)}"]]]
        ]
        app.launchEnvironment["HUDDLZ_UI_HTTP_SCRIPT"] = String(decoding: try! JSONSerialization.data(withJSONObject: routes), as: UTF8.self)
        app.launch()
        XCTAssertTrue(app.buttons["Account"].waitForExistence(timeout: 5))
        return app
    }

    private func signIn(_ app: XCUIApplication) {
        app.buttons["Account"].tap()
        app.textFields["Email"].tap()
        app.textFields["Email"].typeText("neighbor@example.com")
        app.secureTextFields["Password"].tap()
        app.secureTextFields["Password"].typeText("sample-password\n")
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["Done"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
    }

    private func signOut(_ app: XCUIApplication) {
        app.buttons["Sign out"].tap()
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 5))
    }
}
