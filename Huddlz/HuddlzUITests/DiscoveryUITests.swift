import XCTest

@MainActor
final class DiscoveryUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testEventImageAppearsInItsCardAndDetails() {
        let illustrated = coffee.replacingOccurrences(of: "\"thumbnail_url\":null",
                                                     with: "\"thumbnail_url\":null,\"image_url\":\"https://images.example.test/coffee.png\"")
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 90))
        let png = renderer.pngData { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 160, height: 90))
        }
        let app = launch(routes: [
            route(body: page([illustrated])),
            route(path: "/api/json/huddlz/coffee", body: "{\"data\":\(illustrated)}"),
            ["path": "/coffee.png", "query": [:],
             "responses": [["status": 200, "bodyBase64": png.base64EncodedString()]]]
        ])
        let card = app.buttons["huddl-coffee"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let cardImage = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            Self.artworkPixelFraction(card, region: CGRect(x: 16, y: 16,
                width: card.frame.width - 32, height: (card.frame.width - 32) * 9 / 16)) > 0.9
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [cardImage], timeout: 8), .completed)
        card.tap()
        XCTAssertTrue(app.staticTexts["About this huddl"].waitForExistence(timeout: 5))
        let detailImage = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            Self.artworkPixelFraction(app, region: CGRect(x: 20, y: app.navigationBars.firstMatch.frame.maxY + 20,
                width: app.frame.width - 40, height: (app.frame.width - 40) * 9 / 16)) > 0.9
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [detailImage], timeout: 8), .completed)
    }

    func testMissingAndFailedImagesKeepTheFallbackAndEventDetails() {
        for imageResponse in [503, 200, 0] {
            let event = imageResponse == 0 ? coffee : coffee.replacingOccurrences(
                of: "\"thumbnail_url\":null", with: "\"image_url\":\"https://images.example.test/unavailable.png\"")
            let app = launch(routes: [
                route(body: page([event])),
                route(path: "/api/json/huddlz/coffee", body: "{\"data\":\(event)}"),
                route(path: "/unavailable.png", body: "not image data", status: imageResponse)
            ])
            let card = app.buttons["huddl-coffee"]
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            let attachment = XCTAttachment(screenshot: card.screenshot())
            attachment.name = "Fallback for image response \(imageResponse)"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertGreaterThan(Self.artworkPixelFraction(card, fallback: true, region: CGRect(x: 16, y: 16, width: card.frame.width - 32, height: (card.frame.width - 32) * 9 / 16)), 0.01,
                                 "Expected the event-type illustration for image response \(imageResponse)")
            card.tap()
            XCTAssertTrue(app.staticTexts["Bring a mug and meet your neighbors."].waitForExistence(timeout: 5))
            let artwork = CGRect(x: 20, y: app.navigationBars.firstMatch.frame.maxY + 20,
                                 width: app.frame.width - 40, height: (app.frame.width - 40) * 9 / 16)
            XCTAssertGreaterThan(Self.artworkPixelFraction(app, fallback: true, region: artwork), 0.01,
                                 "Expected fallback artwork in details for image response \(imageResponse)")
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            XCTAssertGreaterThan(Self.artworkPixelFraction(card, fallback: true,
                                 region: CGRect(x: 16, y: 16, width: card.frame.width - 32, height: (card.frame.width - 32) * 9 / 16)), 0.01)
            app.terminate()
        }
    }

    private static func artworkPixelFraction(_ element: XCUIElement, fallback: Bool = false, region: CGRect? = nil) -> Double {
        guard var source = element.screenshot().image.cgImage else { return 0 }
        if let region {
            // Crop the artwork so text and navigation cannot satisfy the visual assertion.
            let scale = CGFloat(source.width) / element.frame.width
            guard let cropped = source.cropping(to: region.applying(CGAffineTransform(scaleX: scale, y: scale))) else { return 0 }
            source = cropped
        }
        let width = source.width, height = source.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let count = pixels.withUnsafeMutableBytes { bytes -> Int in
            let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            let data = bytes.bindMemory(to: UInt8.self)
            return stride(from: 0, to: data.count, by: 4).filter {
                if fallback {
                    return data[$0] > 100 && data[$0 + 2] > 80 && Double(data[$0 + 1]) < Double(data[$0]) * 0.8
                }
                return data[$0] < 50 && data[$0 + 1] > 200 && data[$0 + 2] < 50
            }.count
        }
        return Double(count) / Double(width * height)
    }

    func testChoosingAPlaceShowsNearbyResultsAndKeepsFilters() {
        let nearby = coffee.replacingOccurrences(of: "Coffee with neighbors", with: "Nearby coffee")
        let app = launch(routes: [
            route(query: ["query": "coffee", "date_filter": "this_week", "event_type": "in_person",
                          "search_latitude": "29.9012", "search_longitude": "-81.3124",
                          "distance_miles": "25"], body: page([nearby])),
            route(body: page([hike]))
        ], places: [["query": "St. Augustine", "results": [
            ["name": "St. Augustine", "address": "St. Augustine, FL, USA",
             "latitude": 29.9012, "longitude": -81.3124, "timeZone": "America/New_York"]
        ]]])
        XCTAssertTrue(app.buttons["huddl-hike"].waitForExistence(timeout: 5))
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("coffee\n")
        app.buttons["When: All upcoming"].tap()
        app.buttons["This week"].tap()
        app.buttons["Event type: All types"].tap()
        app.buttons["In person"].tap()
        app.buttons["Location: Anywhere"].tap()
        app.textFields["City or postal code"].tap()
        app.textFields["City or postal code"].typeText("St. Augustine\n")
        let place = app.buttons["St. Augustine, FL, USA"]
        XCTAssertTrue(place.waitForExistence(timeout: 5))
        place.tap()
        let card = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@",
                                                   "huddl-coffee", "Nearby coffee")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Location: St. Augustine, FL, USA"].exists)
        XCTAssertTrue(app.buttons["When: This week"].exists)
        XCTAssertTrue(app.buttons["Event type: In person"].exists)
    }

    func testWideningTheDistanceFindsMoreHuddlz() {
        let app = launch(routes: [
            route(query: ["search_latitude": "29.9012", "search_longitude": "-81.3124",
                          "distance_miles": "50"], body: page([coffee, hike])),
            route(query: ["search_latitude": "29.9012", "distance_miles": "25"], body: page([coffee])),
            route(body: page([]))
        ], places: [["query": "St. Augustine", "results": [
            ["name": "St. Augustine", "address": "St. Augustine, FL, USA",
             "latitude": 29.9012, "longitude": -81.3124, "timeZone": "America/New_York"]
        ]]])
        app.buttons["Location: Anywhere"].tap()
        app.textFields["City or postal code"].tap()
        app.textFields["City or postal code"].typeText("St. Augustine\n")
        XCTAssertTrue(app.buttons["St. Augustine, FL, USA"].waitForExistence(timeout: 5))
        app.buttons["St. Augustine, FL, USA"].tap()
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["huddl-hike"].exists)

        app.buttons["Distance: 25 miles"].tap()
        app.buttons["50 miles"].tap()

        XCTAssertTrue(app.buttons["huddl-hike"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["huddl-coffee"].exists)
        XCTAssertTrue(app.buttons["Distance: 50 miles"].exists)
    }

    func testClearingLocationRecoversFromNoNearbyHuddlzAndKeepsSearch() {
        let app = launch(routes: [
            route(query: ["search_latitude": "29.9012"], body: page([])),
            route(query: ["query": "coffee"], body: page([coffee])),
            route(body: page([hike]))
        ], places: [["query": "St. Augustine", "results": [
            ["name": "St. Augustine", "address": "St. Augustine, FL, USA",
             "latitude": 29.9012, "longitude": -81.3124, "timeZone": "America/New_York"]
        ]]])
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("coffee\n")
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
        app.buttons["Location: Anywhere"].tap()
        app.textFields["City or postal code"].tap()
        app.textFields["City or postal code"].typeText("St. Augustine\n")
        XCTAssertTrue(app.buttons["St. Augustine, FL, USA"].waitForExistence(timeout: 5))
        app.buttons["St. Augustine, FL, USA"].tap()
        XCTAssertTrue(app.staticTexts["No huddlz found"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Try a wider distance, another place, or different search filters."].exists)

        app.buttons["Clear location"].tap()

        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["huddl-hike"].exists)
        XCTAssertTrue(app.buttons["Location: Anywhere"].exists)
        XCTAssertFalse(app.buttons["Distance: 25 miles"].exists)
    }

    func testSearchingAndOpeningACardShowsCurrentDetailsWithoutSignIn() throws {
        let updated = coffee.replacingOccurrences(of: "Coffee with neighbors", with: "Coffee with neighbors — updated")
            .replacingOccurrences(of: "2026-09-10T16:00:00Z", with: "2026-09-11T16:00:00Z")
        let app = launch(routes: [
            route(query: ["query": "coffee"], body: page([coffee.replacingOccurrences(of: "Coffee with neighbors", with: "Coffee search result")])),
            route(body: page([coffee, hike])),
            route(path: "/api/json/huddlz/coffee", body: "{\"data\":\(updated)}")
        ])
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))

        XCTAssertTrue(app.buttons["huddl-hike"].exists)
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("coffee\n")
        let matchingCard = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@",
                                                            "huddl-coffee", "Coffee search result")).firstMatch
        XCTAssertTrue(matchingCard.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["huddl-hike"].exists)
        app.buttons["huddl-coffee"].tap()

        XCTAssertTrue(app.staticTexts["Coffee with neighbors — updated"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Bring a mug and meet your neighbors."].exists)
        XCTAssertTrue(app.staticTexts["Juniper Café"].exists)
        XCTAssertTrue(app.staticTexts["America/New_York"].exists)
        let start = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Starts:")).firstMatch
        let end = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Ends:")).firstMatch
        XCTAssertTrue(start.label.contains("Sep 10, 2026"))
        XCTAssertTrue(start.label.contains("9:00"))
        XCTAssertTrue(end.label.contains("Sep 11, 2026"))
        XCTAssertTrue(end.label.contains("12:00"))
    }

    func testClearingAnEmptySearchRestoresDiscovery() {
        let app = launch(routes: [
            route(query: ["query": "no-match"], body: page([])),
            route(body: page([coffee]))
        ])
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("no-match\n")
        XCTAssertTrue(app.staticTexts["No huddlz found"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Clear search and filters"].exists)

        app.buttons["Clear text"].tap()
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["No huddlz found"].exists)
    }

    func testFiltersKeepSearchAndCanBeClearedTogether() {
        let online = coffee.replacingOccurrences(of: "Coffee with neighbors", with: "Coffee online")
            .replacingOccurrences(of: "in_person", with: "virtual")
        let app = launch(routes: [
            route(query: ["query": "coffee", "event_type": "virtual", "date_filter": "this_week"], body: page([])),
            route(query: ["query": "coffee", "event_type": "virtual"], body: page([online])),
            route(query: ["query": "coffee"], body: page([coffee])),
            route(body: page([hike]))
        ])
        XCTAssertTrue(app.buttons["huddl-hike"].waitForExistence(timeout: 5))
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("coffee\n")
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
        app.buttons["Event type: All types"].tap()
        app.buttons["Online"].tap()
        let coffeeCard = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@",
                                                          "huddl-coffee", "Coffee online")).firstMatch
        XCTAssertTrue(coffeeCard.waitForExistence(timeout: 5))
        app.buttons["When: All upcoming"].tap()
        app.buttons["This week"].tap()
        XCTAssertTrue(app.staticTexts["No huddlz found"].waitForExistence(timeout: 5))

        app.buttons["Clear search and filters"].tap()
        XCTAssertTrue(app.buttons["huddl-hike"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Event type: All types"].exists)
        XCTAssertTrue(app.buttons["When: All upcoming"].exists)
    }

    func testRetryingAFailedSearchShowsCards() {
        let response: [String: Any] = [
            "path": "/api/json/huddlz", "query": [:],
            "responses": [["status": 503, "body": "{}"], ["status": 200, "body": page([coffee])]]
        ]
        let app = launch(routes: [response])
        XCTAssertTrue(app.staticTexts["Couldn’t load huddlz"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["huddl-coffee"].exists)

        app.buttons["Try again"].tap()
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Couldn’t load huddlz"].exists)
    }

    func testRemovedHuddlShowsAnUnavailableMessageInsteadOfStaleDetails() {
        let app = launch(routes: [
            route(body: page([coffee])),
            route(path: "/api/json/huddlz/coffee", body: "{}", status: 404)
        ])
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
        app.buttons["huddl-coffee"].tap()
        XCTAssertTrue(app.staticTexts["This huddl is no longer available."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Bring a mug and meet your neighbors."].exists)
        XCTAssertTrue(app.buttons["Try again"].exists)
    }

    func testInaccessibleHuddlShowsAnErrorInsteadOfEventContent() {
        let app = launch(routes: [
            route(body: page([coffee])),
            route(path: "/api/json/huddlz/coffee", body: "{}", status: 403)
        ])
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
        app.buttons["huddl-coffee"].tap()
        XCTAssertTrue(app.staticTexts["Couldn’t load this huddl"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Bring a mug and meet your neighbors."].exists)
        XCTAssertTrue(app.buttons["Try again"].exists)
    }

    private func launch(routes: [[String: Any]], places: [[String: Any]] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        let script = try! JSONSerialization.data(withJSONObject: routes)
        app.launchEnvironment["HUDDLZ_UI_HTTP_SCRIPT"] = String(decoding: script, as: UTF8.self)
        app.launchEnvironment["HUDDLZ_UI_MAP_SCRIPT"] = String(decoding: try! JSONSerialization.data(withJSONObject: places), as: UTF8.self)
        app.launch()
        return app
    }

    private func route(path: String = "/api/json/huddlz", query: [String: String] = [:], body: String, status: Int = 200) -> [String: Any] {
        ["path": path, "query": query, "responses": [["status": status, "body": body]]]
    }

    private func page(_ events: [String]) -> String { "{\"data\":[\(events.joined(separator: ","))]}" }

    private var coffee: String {
        """
        {"type":"huddl","id":"coffee","attributes":{
          "title":"Coffee with neighbors","description":"Bring a mug and meet your neighbors.",
          "starts_at":"2026-09-10T13:00:00Z","ends_at":"2026-09-10T16:00:00Z",
          "time_zone":"America/New_York","event_type":"in_person",
          "physical_location":"Juniper Café","thumbnail_url":null,"lifecycle_state":"published"
        }}
        """
    }

    private var hike: String { coffee.replacingOccurrences(of: "coffee", with: "hike").replacingOccurrences(of: "Coffee with neighbors", with: "Riverside hike") }
}
