import XCTest
import CoreLocation
import Synchronization

@MainActor
final class DiscoveryUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testOpeningAHuddlShowsItsHostingGroup() {
        let event = coffee.dropLast() + #", "relationships":{"group":{"data":{"type":"group","id":"neighbors"}}}}"#
        let detail = """
        {"data":\(event),"included":[
          {"type":"group","id":"other","attributes":{"name":"Other group"}},
          {"type":"group","id":"neighbors","attributes":{"name":"Juniper Neighbors"}}
        ]}
        """
        let app = launch(routes: [
            route(body: page([coffee])),
            route(path: "/api/json/huddlz/coffee", query: ["include": "group", "fields[group]": "name"], body: detail),
            route(path: "/api/json/huddlz/coffee", body: "{\"data\":\(coffee)}")
        ])
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
        app.buttons["huddl-coffee"].tap()
        XCTAssertTrue(app.staticTexts["Hosted by"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Juniper Neighbors"].exists)
        XCTAssertFalse(app.staticTexts["Other group"].exists)
    }

    func testUnavailableOrMissingHostKeepsDetailsWithoutAHostRow() {
        let hidden = coffee.dropLast() + #", "relationships":{"group":{"data":null}}}"#
        for event in [String(hidden), coffee] {
            let app = launch(routes: [
                route(body: page([coffee])),
                route(path: "/api/json/huddlz/coffee", body: "{\"data\":\(event)}")
            ])
            XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
            app.buttons["huddl-coffee"].tap()
            XCTAssertTrue(app.staticTexts["Bring a mug and meet your neighbors."].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["Hosted by"].exists)
        }
    }

    func testVenueMapAndAddressOpenAppleMaps() {
        let maps = XCUIApplication(bundleIdentifier: "com.apple.Maps")
        defer { maps.terminate() }
        for eventType in ["in_person", "hybrid"] {
            let address = "1 Apple Park Way, Cupertino, CA"
            let event = coffee.replacingOccurrences(of: "Juniper Café", with: address)
                .replacingOccurrences(of: "in_person", with: eventType)
            let app = launch(routes: [
                route(body: page([event])),
                route(path: "/api/json/huddlz/coffee", body: "{\"data\":\(event)}")
            ], places: [["query": address, "results": [
                ["name": "Apple Park", "address": address, "latitude": 37.3349, "longitude": -122.0090]
            ]]])
            XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
            app.buttons["huddl-coffee"].tap()
            let map = app.maps.firstMatch
            XCTAssertTrue(map.waitForExistence(timeout: 5))
            let venue = app.buttons["Open location in Maps"]
            if !venue.isHittable { app.swipeUp() }
            XCTAssertTrue(venue.isHittable)
            XCTAssertTrue(venue.label.contains(address))
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertEqual(app.state, .runningForeground)
            XCTAssertNotEqual(maps.state, .runningForeground)
            venue.tap()
            assertMapsOpened(maps)
        }
    }

    func testUnresolvedVenueStillOpensAnAddressSearchInMaps() {
        let maps = XCUIApplication(bundleIdentifier: "com.apple.Maps")
        defer { maps.terminate() }
        let address = "Juniper Café"
        let match: [String: Any] = ["name": address, "address": "1 Oak Street", "latitude": 37.3, "longitude": -122.0]
        let lookups: [[[String: Any]]] = [[], [["query": address, "results": []]],
                                        [["query": address, "results": [match, match]]]]
        for places in lookups {
            let app = launch(routes: [
                route(body: page([coffee])),
                route(path: "/api/json/huddlz/coffee", body: "{\"data\":\(coffee)}")
            ], places: places)
            XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
            app.buttons["huddl-coffee"].tap()
            let venue = app.buttons["Open location in Maps"]
            XCTAssertTrue(venue.waitForExistence(timeout: 5))
            XCTAssertTrue(venue.label.contains(address))
            XCTAssertFalse(app.maps.firstMatch.exists)
            XCTAssertEqual(app.state, .runningForeground)
            XCTAssertNotEqual(maps.state, .runningForeground)
            venue.tap()
            assertMapsOpened(maps)
        }
    }

    private func assertMapsOpened(_ maps: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        // CI can report Maps' foreground state more than 12 seconds after the tap.
        // This bounds the native handoff; it does not wait for live Maps results.
        let opened = maps.wait(for: .runningForeground, timeout: 30)
        if !opened {
            let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screen.name = "Failed Maps handoff"
            screen.lifetime = .keepAlways
            add(screen)
        }
        XCTAssertTrue(opened, "Maps did not enter the foreground (state: \(maps.state.rawValue)).", file: file, line: line)
    }

    func testOnlineAndUnannouncedLocationsHaveNoMapAction() {
        let events = [coffee.replacingOccurrences(of: "in_person", with: "virtual"),
                      coffee.replacingOccurrences(of: "\"Juniper Café\"", with: "null"),
                      coffee.replacingOccurrences(of: "Juniper Café", with: "   ")]
        for event in events {
            let app = launch(routes: [
                route(body: page([event])),
                route(path: "/api/json/huddlz/coffee", body: "{\"data\":\(event)}")
            ])
            XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
            app.buttons["huddl-coffee"].tap()
            XCTAssertTrue(app.staticTexts["About this huddl"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["Open location in Maps"].exists)
            XCTAssertFalse(app.maps.firstMatch.exists)
        }
    }

    func testScrollingLoadsTheNextBatchWithoutMovingExistingCards() {
        let book = coffee.replacingOccurrences(of: "coffee", with: "book")
            .replacingOccurrences(of: "Coffee with neighbors", with: "Neighborhood book club")
        let garden = coffee.replacingOccurrences(of: "coffee", with: "garden")
            .replacingOccurrences(of: "Coffee with neighbors", with: "Community gardening")
        let app = launch(routes: [
            ["path": "/api/json/huddlz", "query": ["page[after]": "book"],
             "responses": [["status": 200, "body": page([garden]), "delaySeconds": 8]]],
            route(body: page([coffee, hike, book], next: "https://huddlz.com/api/json/huddlz?page%5Bafter%5D=book"))
        ])
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["huddl-garden"].exists)
        let progress = app.activityIndicators["pagination-loading"]
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<3 {
            if progress.exists && progress.isHittable { break }
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
                .press(forDuration: 0.1, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(progress.exists && progress.isHittable)
        let lastCard = app.buttons["huddl-book"]
        XCTAssertTrue(lastCard.isHittable)
        let position = lastCard.frame.minY
        XCTAssertTrue(app.buttons["huddl-garden"].waitForExistence(timeout: 12))
        XCTAssertEqual(lastCard.frame.minY, position, accuracy: 2)
        XCTAssertFalse(progress.exists)
        XCTAssertFalse(app.buttons["Load more huddlz"].exists)
    }

    func testFailedNextBatchWaitsForRetryAndKeepsTheCurrentCards() {
        let book = coffee.replacingOccurrences(of: "coffee", with: "book")
        let garden = coffee.replacingOccurrences(of: "coffee", with: "garden")
        let app = launch(routes: [
            ["path": "/api/json/huddlz", "query": ["page[after]": "book"],
             "responses": [["status": 503, "body": "{}"], ["status": 200, "body": page([garden])]]],
            route(body: page([coffee, hike, book], next: "https://huddlz.com/api/json/huddlz?page%5Bafter%5D=book"))
        ])
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
        let retry = app.buttons["Try loading more again"]
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<3 {
            if retry.exists && retry.isHittable { break }
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
                .press(forDuration: 0.1, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(retry.isHittable)
        XCTAssertTrue(app.buttons["huddl-book"].isHittable)
        XCTAssertFalse(app.buttons["huddl-garden"].exists)
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            .press(forDuration: 0.1, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)),
                   withVelocity: .slow, thenHoldForDuration: 0.3)
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            .press(forDuration: 0.1, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)),
                   withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(retry.exists)
        XCTAssertFalse(app.buttons["huddl-garden"].exists)
        retry.tap()
        XCTAssertTrue(app.buttons["huddl-garden"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "huddl-book").count, 1)
        XCTAssertFalse(retry.exists)
    }

    func testScrollingContinuesPastARepeatedBatch() {
        let book = coffee.replacingOccurrences(of: "coffee", with: "book")
        let garden = coffee.replacingOccurrences(of: "coffee", with: "garden")
        let app = launch(routes: [
            route(query: ["page[after]": "book"], body: page([book], next: "https://huddlz.com/api/json/huddlz?page%5Bafter%5D=overlap")),
            route(query: ["page[after]": "overlap"], body: page([garden])),
            route(body: page([coffee, hike, book], next: "https://huddlz.com/api/json/huddlz?page%5Bafter%5D=book"))
        ])
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<3 {
            if app.buttons["huddl-garden"].exists { break }
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
                .press(forDuration: 0.1, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(app.buttons["huddl-garden"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "huddl-book").count, 1)
    }

    func testPullToRefreshShowsNativeProgressAndKeepsSearchAvailable() {
        let app = launch(routes: [[
            "path": "/api/json/huddlz", "query": [:],
            "responses": [["status": 200, "body": page([coffee])],
                          ["status": 200, "body": page([hike]), "delaySeconds": 8]]
        ]])
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
        let heading = app.staticTexts["Find your people."].frame
        // This strip above the resting heading is blank unless the native spinner appears.
        let region = CGRect(x: app.frame.midX - 22, y: heading.minY - 22, width: 44, height: 22)
        let captured = Mutex<Data?>(nil)
        let captureFinished = expectation(description: "Capture native refresh feedback")
        // The drag waits for native animations to finish. Capture the screen during the request.
        DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
            let data = XCUIScreen.main.screenshot().pngRepresentation
            captured.withLock { $0 = data }
            captureFinished.fulfill()
        }
        let scroll = app.scrollViews.firstMatch
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
            .press(forDuration: 0.1, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        wait(for: [captureFinished], timeout: 12)
        let data = captured.withLock { $0 }!
        let screenshot = UIImage(data: data)!
        let attachment = XCTAttachment(image: screenshot)
        attachment.lifetime = .keepAlways
        add(attachment)
        let scale = CGFloat(screenshot.cgImage!.width) / app.frame.width
        let crop = screenshot.cgImage!.cropping(to: region.applying(CGAffineTransform(scaleX: scale, y: scale)))!
        var pixels = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: crop.width, height: crop.height,
                                    bitsPerComponent: 8, bytesPerRow: crop.width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        }
        var brightness: [Int] = []
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let value = Int(pixels[index]) + Int(pixels[index + 1]) + Int(pixels[index + 2])
            brightness.append(value)
        }
        XCTAssertGreaterThan(brightness.max()! - brightness.min()!, 30, "The native spinner must be visible above the heading")
        XCTAssertTrue(app.buttons["huddl-hike"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.searchFields.firstMatch.exists)
    }

    func testFailedRefreshKeepsCardsAndFiltersAndCanBeRetried() {
        let filtered: [String: Any] = [
            "path": "/api/json/huddlz",
            "query": ["query": "coffee", "date_filter": "this_week", "event_type": "in_person"],
            "responses": [["status": 200, "body": page([coffee])],
                          ["status": 503, "body": "{}"],
                          ["status": 200, "body": page([hike])]]
        ]
        let app = launch(routes: [filtered, route(body: page([hike]))])
        XCTAssertTrue(app.buttons["huddl-hike"].waitForExistence(timeout: 5))
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("coffee\n")
        app.buttons["When: All upcoming"].tap()
        app.buttons["This week"].tap()
        app.buttons["Event type: All types"].tap()
        app.buttons["In person"].tap()
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))

        let scroll = app.scrollViews.firstMatch
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            .press(forDuration: 0.1, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        XCTAssertTrue(app.buttons["huddl-coffee"].exists)
        XCTAssertTrue(app.staticTexts["Couldn’t refresh huddlz."].waitForExistence(timeout: 5))
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "coffee")
        XCTAssertTrue(app.buttons["When: This week"].exists)
        XCTAssertTrue(app.buttons["Event type: In person"].exists)
        app.buttons["Try refreshing again"].tap()
        XCTAssertTrue(app.buttons["huddl-hike"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["huddl-coffee"].exists)
        XCTAssertFalse(app.staticTexts["Couldn’t refresh huddlz."].exists)
    }

    func testCurrentLocationFindsNearbyHuddlzOnlyWhenRequestedAndKeepsFilters() {
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 29.9012, longitude: -81.3124))
        defer { XCUIDevice.shared.location = nil }
        let app = launch(routes: [
            route(query: ["query": "coffee", "date_filter": "this_week", "event_type": "in_person",
                          "search_latitude": "29.9012", "search_longitude": "-81.3124", "distance_miles": "25"],
                  body: page([coffee])),
            route(body: page([hike]))
        ], resetLocationPermission: true)
        XCTAssertTrue(app.buttons["huddl-hike"].waitForExistence(timeout: 5))
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertFalse(system.alerts.firstMatch.exists)
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("coffee\n")
        app.buttons["When: All upcoming"].tap()
        app.buttons["This week"].tap()
        app.buttons["Event type: All types"].tap()
        app.buttons["In person"].tap()
        app.buttons["Location: Anywhere"].tap()
        XCTAssertFalse(system.alerts.firstMatch.exists)
        XCTAssertTrue(app.buttons["Use current location"].waitForExistence(timeout: 3))
        app.buttons["Use current location"].tap()
        let allow = system.alerts.buttons["Allow Once"]
        XCTAssertTrue(allow.waitForExistence(timeout: 5))
        allow.tap()
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Location: Current location"].exists)
        XCTAssertTrue(app.buttons["When: This week"].exists)
        XCTAssertTrue(app.buttons["Event type: In person"].exists)
        app.buttons["Clear location"].tap()
        XCTAssertTrue(app.buttons["huddl-hike"].waitForExistence(timeout: 5))
    }

    func testDeniedLocationExplainsPermissionAndStillAllowsManualSearch() {
        let app = launch(routes: [
            route(query: ["search_latitude": "29.9012", "search_longitude": "-81.3124"], body: page([coffee])),
            route(body: page([hike]))
        ], places: [["query": "St. Augustine", "results": [
            ["name": "St. Augustine", "address": "St. Augustine, FL, USA", "latitude": 29.9012,
             "longitude": -81.3124, "timeZone": "America/New_York"]
        ]]], resetLocationPermission: true)
        XCTAssertTrue(app.buttons["huddl-hike"].waitForExistence(timeout: 5))
        app.buttons["Location: Anywhere"].tap()
        app.buttons["Use current location"].tap()
        let deny = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Don’t Allow"]
        XCTAssertTrue(deny.waitForExistence(timeout: 5))
        deny.tap()
        let explanation = app.staticTexts["Location access is off. Allow access in Settings, or search for a city or postal code."]
        XCTAssertTrue(explanation.waitForExistence(timeout: 5))
        app.buttons["Use current location"].tap()
        XCTAssertTrue(explanation.exists)
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists)
        app.textFields["City or postal code"].tap()
        app.textFields["City or postal code"].typeText("St. Augustine\n")
        let place = app.buttons["St. Augustine, FL, USA"]
        XCTAssertTrue(place.waitForExistence(timeout: 5))
        place.tap()
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Location: St. Augustine, FL, USA"].exists)
    }

    func testUnavailableLocationCanBeRetriedAndManualSearchStaysAvailable() {
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 29.9012, longitude: -81.3124))
        defer { XCUIDevice.shared.location = nil }
        let app = launch(routes: [
            route(query: ["search_latitude": "29.9012", "search_longitude": "-81.3124"], body: page([coffee])),
            route(body: page([hike]))
        ], resetLocationPermission: true, failFirstLocation: true)
        XCTAssertTrue(app.buttons["huddl-hike"].waitForExistence(timeout: 5))
        app.buttons["Location: Anywhere"].tap()
        app.buttons["Use current location"].tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow Once"]
        XCTAssertTrue(allow.waitForExistence(timeout: 5))
        allow.tap()
        XCTAssertTrue(app.staticTexts["Your location couldn’t be found. Try again or search for a city or postal code."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["City or postal code"].isEnabled)
        XCTAssertTrue(app.buttons["Use current location"].isEnabled)
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 29.9012, longitude: -81.3124))
        app.buttons["Use current location"].tap()
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 15))
    }

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
        XCTAssertFalse(app.searchFields.firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Bring a mug and meet your neighbors."].exists)
        XCTAssertTrue(app.staticTexts["Juniper Café"].exists)
        XCTAssertTrue(app.staticTexts["America/New_York"].exists)
        let start = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Starts:")).firstMatch
        let end = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Ends:")).firstMatch
        XCTAssertTrue(start.label.contains("Sep 10, 2026"))
        XCTAssertTrue(start.label.contains("9:00"))
        XCTAssertTrue(end.label.contains("Sep 11, 2026"))
        XCTAssertTrue(end.label.contains("12:00"))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "coffee")
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

    private func launch(routes: [[String: Any]], places: [[String: Any]] = [], resetLocationPermission: Bool = false, failFirstLocation: Bool = false) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        if resetLocationPermission { app.resetAuthorizationStatus(for: .location) }
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        let script = try! JSONSerialization.data(withJSONObject: routes)
        app.launchEnvironment["HUDDLZ_UI_HTTP_SCRIPT"] = String(decoding: script, as: UTF8.self)
        app.launchEnvironment["HUDDLZ_UI_MAP_SCRIPT"] = String(decoding: try! JSONSerialization.data(withJSONObject: places), as: UTF8.self)
        if failFirstLocation { app.launchEnvironment["HUDDLZ_UI_LOCATION_FAIL_FIRST"] = "1" }
        app.launch()
        return app
    }

    private func route(path: String = "/api/json/huddlz", query: [String: String] = [:], body: String, status: Int = 200) -> [String: Any] {
        ["path": path, "query": query, "responses": [["status": status, "body": body]]]
    }

    private func page(_ events: [String], next: String? = nil) -> String {
        let link = next.map { "\"\($0)\"" } ?? "null"
        return "{\"data\":[\(events.joined(separator: ","))],\"links\":{\"next\":\(link)}}"
    }

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
