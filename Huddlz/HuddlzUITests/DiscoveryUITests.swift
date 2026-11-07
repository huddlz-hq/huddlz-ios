import XCTest
import CoreLocation
import Synchronization

// Separate classes let Xcode distribute independent journeys across simulators.
@MainActor
final class DiscoveryUITests: DiscoveryUITestCase {
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
        search.typeAfterFocusing("coffee\n")
        let matchingCard = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@",
                                                            "huddl-coffee", "Coffee search result")).firstMatch
        XCTAssertTrue(matchingCard.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["huddl-hike"].exists)
        app.buttons["huddl-coffee"].tap()

        XCTAssertTrue(app.staticTexts["Coffee with neighbors — updated"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.searchFields.firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Bring a mug and meet your neighbors."].exists)
        XCTAssertTrue(app.staticTexts["Juniper Café"].exists)
        // The zone is named in everyday words, and only when it differs from the phone's (see HuddlDetailBehaviorTests).
        XCTAssertFalse(app.staticTexts["America/New_York"].exists)
        // The date card names the day, then the range in the event's zone; a later end day is spelled out.
        XCTAssertTrue(app.staticTexts["Thursday, September 10"].exists)
        let range = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "9:00")).firstMatch
        XCTAssertEqual(range.label.replacingOccurrences(of: "\u{202F}", with: " "), "9:00 AM – Fri, Sep 11 at 12:00 PM EDT")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "coffee")
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
}

@MainActor
final class DiscoveryPagingUITests: DiscoveryUITestCase {
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

    func testPullToRefreshShowsNativeProgressAndKeepsSearchAvailable() {
        let app = launch(routes: [[
            "path": "/api/json/huddlz", "query": [:],
            "responses": [["status": 200, "body": page([coffee])],
                          ["status": 200, "body": page([hike]), "delaySeconds": 8]]
        ]])
        XCTAssertTrue(app.buttons["huddl-coffee"].waitForExistence(timeout: 5))
        let wordmark = app.staticTexts["huddlz"].frame
        // This strip above the resting wordmark row is blank unless the native spinner appears.
        let region = CGRect(x: app.frame.midX - 22, y: wordmark.minY - 22, width: 44, height: 22)
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
}

@MainActor
final class DiscoveryLocationUITests: DiscoveryUITestCase {
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
        app.searchFields.firstMatch.typeAfterFocusing("coffee\n")
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
}

@MainActor
final class DiscoveryVenueUITests: DiscoveryUITestCase {
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
}

@MainActor
final class DiscoveryArtworkUITests: DiscoveryUITestCase {
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
            Self.artworkPixelFraction(card, region: Self.cardArtwork(card)) > 0.9
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [cardImage], timeout: 8), .completed)
        card.tap()
        XCTAssertTrue(app.staticTexts["About this huddl"].waitForExistence(timeout: 5))
        let detailImage = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            Self.artworkPixelFraction(app, region: Self.detailArtwork(app)) > 0.9
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [detailImage], timeout: 8), .completed)
    }
}

@MainActor
class DiscoveryUITestCase: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    fileprivate func assertMapsOpened(_ maps: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
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

    /// The card cover below its date stamp and tag, so the glass overlays cannot skew the pixel count.
    fileprivate static func cardArtwork(_ card: XCUIElement) -> CGRect {
        CGRect(x: 8, y: 64, width: card.frame.width - 16, height: card.frame.width * 9 / 16 - 64)
    }

    /// The upper part of the full-width detail cover, above the fade into the page background.
    fileprivate static func detailArtwork(_ app: XCUIApplication) -> CGRect {
        CGRect(x: 0, y: app.navigationBars.firstMatch.frame.maxY, width: app.frame.width, height: app.frame.width * 9 / 16 * 0.55)
    }

    fileprivate static func artworkPixelFraction(_ element: XCUIElement, fallback: Bool = false, region: CGRect? = nil) -> Double {
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
                    // The event-type symbol is drawn in the teal accent in both appearances.
                    return data[$0] < 90 && data[$0 + 1] > 100 && data[$0 + 2] > 100 && data[$0 + 1] > data[$0] * 2
                }
                return data[$0] < 50 && data[$0 + 1] > 200 && data[$0 + 2] < 50
            }.count
        }
        return Double(count) / Double(width * height)
    }

    fileprivate func launch(routes: [[String: Any]], places: [[String: Any]] = [], resetLocationPermission: Bool = false, failFirstLocation: Bool = false) -> XCUIApplication {
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

    fileprivate func route(path: String = "/api/json/huddlz", query: [String: String] = [:], body: String, status: Int = 200) -> [String: Any] {
        ["path": path, "query": query, "responses": [["status": status, "body": body]]]
    }

    fileprivate func page(_ events: [String], next: String? = nil) -> String {
        let link = next.map { "\"\($0)\"" } ?? "null"
        return "{\"data\":[\(events.joined(separator: ","))],\"links\":{\"next\":\(link)}}"
    }

    fileprivate var coffee: String {
        """
        {"type":"huddl","id":"coffee","attributes":{
          "title":"Coffee with neighbors","description":"Bring a mug and meet your neighbors.",
          "starts_at":"2026-09-10T13:00:00Z","ends_at":"2026-09-10T16:00:00Z",
          "time_zone":"America/New_York","event_type":"in_person",
          "physical_location":"Juniper Café","thumbnail_url":null,"lifecycle_state":"published"
        }}
        """
    }

    fileprivate var hike: String { coffee.replacingOccurrences(of: "coffee", with: "hike").replacingOccurrences(of: "Coffee with neighbors", with: "Riverside hike") }
}
