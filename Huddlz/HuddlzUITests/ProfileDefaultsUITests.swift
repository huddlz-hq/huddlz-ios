import XCTest

@MainActor
final class ProfileDefaultsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testSigningInAndReopeningUseTheCurrentProfileCity() {
        let app = launch(city: "Austin, TX", latitude: 30.2672, longitude: -97.7431, timeZone: "America/Chicago")
        app.buttons["Account"].tap()
        app.textFields["Email"].tap()
        app.textFields["Email"].typeText("neighbor@example.com")
        app.secureTextFields["Password"].tap()
        app.secureTextFields["Password"].typeText("sample-password\n")
        XCTAssertTrue(app.buttons["huddl-nearby"].waitForExistence(timeout: 60))
        XCTAssertTrue(app.buttons["Location: Austin, TX"].exists)
        XCTAssertTrue(app.buttons["Distance: 25 miles"].exists)
        XCTAssertFalse(app.buttons["huddl-anywhere"].exists)

        app.buttons["Clear location"].tap()
        XCTAssertTrue(app.buttons["huddl-anywhere"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Location: Anywhere"].exists)

        app.terminate()
        setRoutes(app, city: "Denver, CO", latitude: 39.7392, longitude: -104.9903, timeZone: "America/Denver")
        app.launch()
        XCTAssertTrue(app.buttons["huddl-nearby"].waitForExistence(timeout: 60))
        XCTAssertTrue(app.buttons["Location: Denver, CO"].exists)
        app.buttons["Account"].tap()
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 5))
        app.buttons["Sign out"].tap()
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 60))
    }

    private func launch(city: String, latitude: Double, longitude: Double, timeZone: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HUDDLZ_UI_SESSION_ID"] = UUID().uuidString
        setRoutes(app, city: city, latitude: latitude, longitude: longitude, timeZone: timeZone)
        app.launch()
        XCTAssertTrue(app.buttons["Account"].waitForExistence(timeout: 5))
        return app
    }

    private func setRoutes(_ app: XCUIApplication, city: String, latitude: Double, longitude: Double, timeZone: String) {
        let user = #"{"id":"neighbor","email":"neighbor@example.com","display_name":"Our Neighbor"}"#
        let profile = """
        {"id":"neighbor","search_defaults":{"home_location":{
          "label":"\(city)","latitude":\(latitude),"longitude":\(longitude),"time_zone":"\(timeZone)"
        },"distance_miles":25}}
        """
        let routes: [[String: Any]] = [
            route("/api/auth/sign_in", body: "{\"token\":\"fixture-token\",\"user\":\(user)}"),
            route("/api/auth/me", body: "{\"user\":\(user)}"),
            route("/api/auth/sign_out", body: "{}"),
            route("/api/json/profile", body: profile),
            route("/api/json/huddlz", query: ["search_latitude": String(latitude), "search_longitude": String(longitude),
                                            "search_time_zone": timeZone, "distance_miles": "25"], body: page(id: "nearby")),
            route("/api/json/huddlz", body: page(id: "anywhere"))
        ]
        app.launchEnvironment["HUDDLZ_UI_HTTP_SCRIPT"] = String(decoding: try! JSONSerialization.data(withJSONObject: routes), as: UTF8.self)
    }

    private func route(_ path: String, query: [String: String] = [:], body: String) -> [String: Any] {
        ["path": path, "query": query, "responses": [["status": 200, "body": body]]]
    }

    private func page(id: String) -> String {
        """
        {"data":[{"id":"\(id)","type":"huddl","attributes":{
          "title":"Coffee with neighbors","starts_at":"2026-09-10T13:00:00Z","ends_at":"2026-09-10T16:00:00Z",
          "time_zone":"America/Chicago","event_type":"in_person","lifecycle_state":"published"
        }}]}
        """
    }
}
