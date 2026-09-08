import XCTest

@MainActor
final class RegistrationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testCreatingAnAccountRequiresAcceptanceAndReturnsToBrowsingWithASavedSession() {
        let app = launch()
        app.buttons["When: All upcoming"].tap()
        app.buttons["This week"].tap()
        openRegistration(app)
        fillRegistration(app)
        XCTAssertTrue(app.buttons["Terms of Service"].exists)
        XCTAssertTrue(app.buttons["Code of Conduct"].exists)
        XCTAssertTrue(app.buttons["Privacy Policy"].exists)
        XCTAssertFalse(app.buttons["Create account"].isEnabled)
        app.switches["Accept legal documents"].tap()
        app.buttons["Create account"].tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["Close account"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["When: This week"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Account"].waitForExistence(timeout: 5))
        app.buttons["Account"].tap()
        XCTAssertTrue(app.staticTexts["Our Neighbor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["neighbor@example.com"].exists)
        app.buttons["Sign out"].tap()
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 5))
    }

    func testRejectedRegistrationKeepsEntriesAndAllowsCorrection() {
        let app = launch(responses: [
            ["status": 422, "body": #"{"errors":[{"field":"email","message":"Enter a valid email address."}]}"#],
            ["status": 201, "body": "{\"token\":\"fixture-token\",\"user\":\(user)}"]
        ])
        openRegistration(app)
        fillRegistration(app, email: "neighbor")
        app.switches["Accept legal documents"].tap()
        app.buttons["Create account"].tap()
        XCTAssertTrue(app.staticTexts["Enter a valid email address."].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Display name"].value as? String, "Our Neighbor")
        XCTAssertEqual(app.textFields["Email"].value as? String, "neighbor")
        XCTAssertTrue(app.buttons["Create account"].isEnabled)
        app.textFields["Email"].tap()
        // Correct the form through the native keyboard, then retry.
        app.textFields["Email"].typeText("@example.com\n")
        app.secureTextFields["Confirm password"].tap()
        app.secureTextFields["Confirm password"].typeText("\n")
        app.buttons["Create account"].tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["Close account"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        app.buttons["Account"].tap()
        XCTAssertTrue(app.staticTexts["Our Neighbor"].waitForExistence(timeout: 5))
        app.buttons["Sign out"].tap()
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 5))
    }

    private let user = #"{"id":"neighbor","email":"neighbor@example.com","display_name":"Our Neighbor"}"#

    private func launch(responses: [[String: Any]]? = nil) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HUDDLZ_UI_SESSION_ID"] = UUID().uuidString
        let routes: [[String: Any]] = [
            ["path": "/api/json/huddlz", "query": [:], "responses": [["status": 200, "body": "{\"data\":[]}"]]],
            ["path": "/api/auth/register", "query": [:], "responses": responses ?? [["status": 201, "body": "{\"token\":\"fixture-token\",\"user\":\(user)}"]]],
            ["path": "/api/auth/me", "query": [:], "responses": [["status": 200, "body": "{\"user\":\(user)}"]]],
            ["path": "/api/auth/sign_out", "query": [:], "responses": [["status": 204, "body": ""]]]
        ]
        app.launchEnvironment["HUDDLZ_UI_HTTP_SCRIPT"] = String(decoding: try! JSONSerialization.data(withJSONObject: routes), as: UTF8.self)
        app.launch()
        XCTAssertTrue(app.buttons["Account"].waitForExistence(timeout: 5))
        return app
    }

    private func openRegistration(_ app: XCUIApplication) {
        app.buttons["Account"].tap()
        XCTAssertTrue(app.buttons["Create an account"].waitForExistence(timeout: 3))
        app.buttons["Create an account"].tap()
        XCTAssertTrue(app.textFields["Display name"].waitForExistence(timeout: 3))
    }

    private func fillRegistration(_ app: XCUIApplication, email: String = "neighbor@example.com") {
        app.textFields["Display name"].tap()
        app.textFields["Display name"].typeText("Our Neighbor")
        app.textFields["Email"].tap()
        app.textFields["Email"].typeText(email)
        app.secureTextFields["Password"].tap()
        app.secureTextFields["Password"].typeText("sample-password")
        app.secureTextFields["Confirm password"].tap()
        app.secureTextFields["Confirm password"].typeText("sample-password\n")
    }
}
