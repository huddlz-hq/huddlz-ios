import XCTest
import CoreLocation

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
        XCTAssertTrue(app.staticTexts["Where should we find huddlz?"].waitForExistence(timeout: 5))
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists)
        app.buttons["Not now"].tap()
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
        XCTAssertTrue(app.staticTexts["Where should we find huddlz?"].waitForExistence(timeout: 5))
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists)
        app.buttons["Not now"].tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["Close account"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        app.buttons["Account"].tap()
        XCTAssertTrue(app.staticTexts["Our Neighbor"].waitForExistence(timeout: 5))
        app.buttons["Sign out"].tap()
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 5))
    }

    func testChoosingACityRequiresConfirmationThenFindsNearbyHuddlz() {
        let app = launch()
        app.buttons["When: All upcoming"].tap()
        app.buttons["This week"].tap()
        openRegistration(app)
        fillRegistration(app)
        app.switches["Accept legal documents"].tap()
        app.buttons["Create account"].tap()
        XCTAssertTrue(app.buttons["Choose a city"].waitForExistence(timeout: 5))
        capture(app, name: "Signup city choices")
        app.buttons["Choose a city"].tap()
        app.textFields["City"].tap()
        app.textFields["City"].typeText("St. Augustine\n")
        let city = app.buttons["St. Augustine, FL, USA"]
        XCTAssertTrue(city.waitForExistence(timeout: 5))
        city.tap()
        XCTAssertTrue(app.buttons["Save home city"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["St. Augustine, FL, USA"].exists)
        capture(app, name: "Confirm home city")
        app.buttons["Save home city"].tap()
        XCTAssertTrue(app.buttons["Location: St. Augustine, FL, USA"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["When: This week"].exists)
    }

    func testCurrentLocationSuggestsACityForConfirmation() {
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 29.9012, longitude: -81.3124))
        defer { XCUIDevice.shared.location = nil }
        let app = launch(resetLocation: true)
        openRegistration(app)
        fillRegistration(app)
        app.switches["Accept legal documents"].tap()
        app.buttons["Create account"].tap()
        XCTAssertTrue(app.buttons["Use current location"].waitForExistence(timeout: 5))
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertFalse(system.alerts.firstMatch.exists)
        app.buttons["Use current location"].tap()
        let allow = system.alerts.buttons["Allow Once"]
        XCTAssertTrue(allow.waitForExistence(timeout: 5))
        allow.tap()
        XCTAssertTrue(app.staticTexts["St. Augustine, FL, USA"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Save home city"].exists)
        app.buttons["Not now"].tap()
        XCTAssertTrue(app.buttons["Location: Anywhere"].waitForExistence(timeout: 5))
    }

    func testFailedCitySaveKeepsTheCityAndCanRetry() {
        verifyFailedCitySave(retry: true)
    }

    func testFailedCitySaveCanBeSkippedWithoutChangingSearch() {
        verifyFailedCitySave(retry: false)
    }

    private func verifyFailedCitySave(retry: Bool) {
        let app = launch(saveResponses: [
            ["status": 200, "body": #"{"data":{"updateHomeLocation":{"result":null,"errors":[{"__typename":"MutationError"}]}}}"#],
            ["status": 200, "body": savedCity]
        ])
        openRegistration(app)
        fillRegistration(app)
        app.switches["Accept legal documents"].tap()
        app.buttons["Create account"].tap()
        XCTAssertTrue(app.buttons["Choose a city"].waitForExistence(timeout: 5))
        app.buttons["Choose a city"].tap()
        app.textFields["City"].tap()
        app.textFields["City"].typeText("St. Augustine\n")
        XCTAssertTrue(app.buttons["St. Augustine, FL, USA"].waitForExistence(timeout: 5))
        app.buttons["St. Augustine, FL, USA"].tap()
        app.buttons["Save home city"].tap()
        XCTAssertTrue(app.staticTexts["Couldn’t save your city. Try again, or do this later."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["St. Augustine, FL, USA"].exists)
        XCTAssertTrue(app.buttons["Not now"].isEnabled)
        if retry {
            app.buttons["Retry"].tap()
            XCTAssertTrue(app.buttons["Location: St. Augustine, FL, USA"].waitForExistence(timeout: 5))
        } else {
            app.buttons["Not now"].tap()
            XCTAssertTrue(app.buttons["Location: Anywhere"].waitForExistence(timeout: 5))
            app.buttons["Account"].tap()
            XCTAssertTrue(app.staticTexts["Our Neighbor"].waitForExistence(timeout: 5))
        }
    }

    func testDeniedLocationKeepsCitySearchAndSkippingAvailable() {
        verifyLocationRecovery(denied: true)
    }

    func testUnavailableLocationKeepsCitySearchAndSkippingAvailable() {
        verifyLocationRecovery(denied: false)
    }

    private func verifyLocationRecovery(denied: Bool) {
        let app = launch(resetLocation: true, failFirstLocation: !denied)
        openRegistration(app)
        fillRegistration(app)
        app.switches["Accept legal documents"].tap()
        app.buttons["Create account"].tap()
        XCTAssertTrue(app.buttons["Use current location"].waitForExistence(timeout: 5))
        app.buttons["Use current location"].tap()
        let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons[denied ? "Don’t Allow" : "Allow Once"]
        XCTAssertTrue(permission.waitForExistence(timeout: 5))
        permission.tap()
        let message = denied ? "Location access is off. Allow access in Settings, or search for a city or postal code." :
            "Your location couldn’t be found. Try again or search for a city or postal code."
        XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 5))
        if denied {
            app.buttons["Use current location"].tap()
            XCTAssertTrue(app.buttons["Use current location"].isEnabled)
            XCTAssertTrue(app.staticTexts[message].exists)
        }
        XCTAssertTrue(app.buttons["Not now"].isEnabled)
        app.buttons["Choose a city"].tap()
        app.textFields["City"].tap()
        app.textFields["City"].typeText("St. Augustine\n")
        XCTAssertTrue(app.buttons["St. Augustine, FL, USA"].waitForExistence(timeout: 5))
        app.buttons["St. Augustine, FL, USA"].tap()
        XCTAssertTrue(app.buttons["Save home city"].waitForExistence(timeout: 5))
        app.buttons["Not now"].tap()
        XCTAssertTrue(app.buttons["Location: Anywhere"].waitForExistence(timeout: 5))
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private let savedCity = #"{"data":{"updateHomeLocation":{"result":{"id":"neighbor","homeLocation":"St. Augustine, FL, USA"},"errors":[]}}}"#

    private let user = #"{"id":"neighbor","email":"neighbor@example.com","display_name":"Our Neighbor"}"#

    private func launch(responses: [[String: Any]]? = nil, resetLocation: Bool = false, saveResponses: [[String: Any]]? = nil, failFirstLocation: Bool = false) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HUDDLZ_UI_SESSION_ID"] = UUID().uuidString
        let routes: [[String: Any]] = [
            ["path": "/api/json/huddlz", "query": [:], "responses": [["status": 200, "body": "{\"data\":[]}"]]],
            ["path": "/api/auth/register", "query": [:], "responses": responses ?? [["status": 201, "body": "{\"token\":\"fixture-token\",\"user\":\(user)}"]]],
            ["path": "/api/auth/me", "query": [:], "responses": [["status": 200, "body": "{\"user\":\(user)}"]]],
            ["path": "/gql", "query": [:], "responses": saveResponses ?? [["status": 200, "body": savedCity]]],
            ["path": "/api/auth/sign_out", "query": [:], "responses": [["status": 204, "body": ""]]]
        ]
        app.launchEnvironment["HUDDLZ_UI_HTTP_SCRIPT"] = String(decoding: try! JSONSerialization.data(withJSONObject: routes), as: UTF8.self)
        app.launchEnvironment["HUDDLZ_UI_MAP_SCRIPT"] = #"[{"query":"St. Augustine","results":[{"name":"St. Augustine","address":"St. Augustine, FL, USA","latitude":29.9,"longitude":-81.31,"timeZone":"America/New_York"}]}]"#
        app.launchEnvironment["HUDDLZ_UI_REVERSE_CITY"] = "St. Augustine"
        if failFirstLocation { app.launchEnvironment["HUDDLZ_UI_LOCATION_FAIL_FIRST"] = "1" }
        if resetLocation { app.resetAuthorizationStatus(for: .location) }
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
