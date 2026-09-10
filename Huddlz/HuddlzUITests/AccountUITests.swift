import XCTest

@MainActor
final class AccountUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testRequestingPasswordResetShowsConfirmationAndKeepsEmailForSignIn() {
        let app = launch()
        app.buttons["Account"].tap()
        app.textFields["Email"].tap()
        app.textFields["Email"].typeText("neighbor@example.com")
        app.buttons["Forgot password?"].tap()
        XCTAssertTrue(app.staticTexts["Reset your password"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.textFields["Email"].value as? String, "neighbor@example.com")
        app.buttons["Send reset link"].tap()
        XCTAssertTrue(app.staticTexts["If an account exists for this email, we’ll send a reset link."].waitForExistence(timeout: 5))
        app.buttons["Back to sign in"].tap()
        XCTAssertTrue(app.secureTextFields["Password"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.textFields["Email"].value as? String, "neighbor@example.com")
    }

    func testFailedPasswordResetShowsAnErrorAndAllowsRetry() {
        for (status, message) in [
            (503, "Couldn’t request a reset link. Check your connection and try again."),
            (429, "Too many requests. Please try again later.")
        ] {
            let app = launch(resetResponses: [["status": status, "body": "{}"], ["status": 204, "body": ""]])
            app.buttons["Account"].tap()
            app.buttons["Forgot password?"].tap()
            app.textFields["Email"].tap()
            app.textFields["Email"].typeText("neighbor@example.com\n")
            XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 5))
            XCTAssertEqual(app.textFields["Email"].value as? String, "neighbor@example.com")
            XCTAssertFalse(app.staticTexts["Check your email"].exists)
            XCTAssertTrue(app.buttons["Send reset link"].isEnabled)
            app.buttons["Send reset link"].tap()
            XCTAssertTrue(app.staticTexts["If an account exists for this email, we’ll send a reset link."].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts[message].exists)
            app.terminate()
        }
    }

    func testShowingAndHidingPasswordPreservesEntryAndCanSignIn() {
        let app = launch()
        app.buttons["Account"].tap()
        app.textFields["Email"].tap()
        app.textFields["Email"].typeText("neighbor@example.com")
        app.secureTextFields["Password"].tap()
        app.secureTextFields["Password"].typeText("sample-password")
        XCTAssertTrue(app.buttons["Show password"].exists)
        app.buttons["Show password"].tap()
        XCTAssertEqual(app.textFields["Password"].value as? String, "sample-password")
        app.buttons["Hide password"].tap()
        XCTAssertTrue(app.secureTextFields["Password"].exists)
        app.buttons["Sign in"].tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["Close account"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: accountOperationTimeout), .completed)
        app.buttons["Account"].tap()
        XCTAssertTrue(app.staticTexts["Our Neighbor"].waitForExistence(timeout: 5))
        signOut(app)
    }

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
        let app = launch(savedSession: true)
        app.buttons["Account"].tap()
        XCTAssertTrue(app.staticTexts["Our Neighbor"].waitForExistence(timeout: 60))
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
        // Hosted Simulator can drop the first focus tap after keyboard dismissal.
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) {
            app.secureTextFields["Password"].tap()
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.secureTextFields["Password"].typeText("sample-password\n")
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["Close account"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: accountOperationTimeout), .completed)
        app.buttons["Account"].tap()
        XCTAssertTrue(app.staticTexts["Our Neighbor"].waitForExistence(timeout: 5))
        signOut(app)
    }

    private let user = #"{"id":"neighbor","email":"neighbor@example.com","display_name":"Our Neighbor"}"#

    private func launch(savedSession: Bool = false, signInResponses: [[String: Any]]? = nil, resetResponses: [[String: Any]]? = nil) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HUDDLZ_UI_SESSION_ID"] = UUID().uuidString
        let routes: [[String: Any]] = [
            ["path": "/api/auth/password_reset", "query": [:], "responses": resetResponses ?? [["status": 204, "body": ""]]],
            ["path": "/api/json/huddlz", "query": [:], "responses": [["status": 200, "body": "{\"data\":[]}"]]],
            ["path": "/api/auth/me", "query": [:], "responses": [["status": 200, "body": "{\"user\":\(user)}"]]],
            ["path": "/api/auth/sign_out", "query": [:], "responses": [["status": 204, "body": ""]]],
            ["path": "/api/auth/sign_in", "query": [:], "responses": signInResponses ?? [
                ["status": 200, "body": "{\"token\":\"fixture-token\",\"user\":\(user)}"]]]
        ]
        app.launchEnvironment["HUDDLZ_UI_HTTP_SCRIPT"] = String(decoding: try! JSONSerialization.data(withJSONObject: routes), as: UTF8.self)
        if savedSession { app.launchWithSavedSession() } else { app.launch() }
        XCTAssertTrue(app.buttons["Account"].waitForExistence(timeout: 5))
        return app
    }

    private func signIn(_ app: XCUIApplication) {
        app.buttons["Account"].tap()
        app.textFields["Email"].tap()
        app.textFields["Email"].typeText("neighbor@example.com")
        app.secureTextFields["Password"].tap()
        app.secureTextFields["Password"].typeText("sample-password\n")
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["Close account"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: accountOperationTimeout), .completed)
    }

    private func signOut(_ app: XCUIApplication) {
        app.buttons["Sign out"].tap()
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: accountOperationTimeout))
    }

    // Hosted Simulator Keychain operations can take tens of seconds. These waits
    // end as soon as the account operation completes; they are not performance tests.
    private let accountOperationTimeout: TimeInterval = 60
}
