import Foundation
import Testing
@testable import Huddlz

@MainActor
struct HuddlDetailBehaviorTests {
    @Test("Cards show the weekday, start time, and zone where the huddl happens, plus its type and place")
    func cardDetails() async {
        let hybrid = HTTPFixture.hike.replacingOccurrences(of: "in_person", with: "hybrid")
        let online = HTTPFixture.hike.replacingOccurrences(of: "\"hike\"", with: "\"online\"")
            .replacingOccurrences(of: "in_person", with: "virtual")
        let discovery = DiscoveryStore(client: DiscoveryClient { request in
            HTTPFixture.response(request, body: HTTPFixture.page([HTTPFixture.coffee, hybrid, online]))
        })
        await discovery.search(DiscoveryQuery())
        let cards = Dictionary(uniqueKeysWithValues: discovery.huddlz.map { ($0.id, $0) })
        let coffee = cards["coffee"]
        #expect(coffee?.startTime.replacingOccurrences(of: "\u{202F}", with: " ") == "Thu 9:00 AM")
        #expect(coffee?.timeZoneLabel == "EDT")
        #expect(coffee?.attributes.eventType.title == "In person")
        #expect(coffee?.location == "Juniper Café")
        #expect(cards["hike"]?.attributes.eventType.title == "Hybrid")
        #expect(cards["hike"]?.location == "Location to be announced")
        #expect(cards["online"]?.location == "Online")
    }

    @Test("Opening a huddl names the group that hosts it, not another included group")
    func hostingGroup() async throws {
        let event = HTTPFixture.coffee.dropLast() + #", "relationships":{"group":{"data":{"type":"group","id":"neighbors"}}}}"#
        let client = DiscoveryClient { request in
            #expect(HTTPFixture.parameters(request)["include"] == "group")
            return HTTPFixture.response(request, body: """
            {"data":\(event),"included":[
              {"type":"group","id":"other","attributes":{"name":"Other group"}},
              {"type":"group","id":"neighbors","attributes":{"name":"Juniper Neighbors"}}
            ]}
            """)
        }
        let huddl = try await client.detail(id: "coffee")
        #expect(huddl.hostName == "Juniper Neighbors")
        #expect(huddl.relationships?.group?.data?.id == "neighbors")
    }

    @Test("Opening a huddl asks for its group's slug and offers the huddl's web page")
    func webPage() async throws {
        let event = HTTPFixture.coffee.dropLast() + #", "relationships":{"group":{"data":{"type":"group","id":"neighbors"}}}}"#
        let client = DiscoveryClient { request in
            #expect(HTTPFixture.parameters(request)["fields[group]"] == "name,slug")
            return HTTPFixture.response(request, body: """
            {"data":\(event),"included":[{"type":"group","id":"neighbors","attributes":{"name":"Juniper Neighbors","slug":"juniper-neighbors"}}]}
            """)
        }
        let huddl = try await client.detail(id: "coffee")
        #expect(huddl.webURL?.absoluteString == "https://huddlz.com/groups/juniper-neighbors/huddlz/coffee")
    }

    @Test("Without its group's slug, a huddl offers no web page to share")
    func noWebPageWithoutSlug() async throws {
        let client = DiscoveryClient { request in
            HTTPFixture.response(request, body: "{\"data\":\(HTTPFixture.coffee)}")
        }
        let huddl = try await client.detail(id: "coffee")
        #expect(huddl.webURL == nil)
    }

    @Test("A huddl in another time zone names that zone in everyday words; one in your own zone leaves it unsaid")
    func zoneName() async throws {
        let client = DiscoveryClient { request in
            HTTPFixture.response(request, body: "{\"data\":\(HTTPFixture.coffee)}")
        }
        let huddl = try await client.detail(id: "coffee")
        let english = Locale(identifier: "en_US")
        #expect(huddl.zoneName(comparedWith: TimeZone(identifier: "America/Los_Angeles")!, locale: english) == "Eastern Time")
        #expect(huddl.zoneName(comparedWith: TimeZone(identifier: "America/New_York")!, locale: english) == nil)
    }

    @Test("A withheld or missing host keeps the details without naming a host", arguments: [
        #", "relationships":{"group":{"data":null}}}"#,
        #", "relationships":{"group":{"data":{"type":"group","id":"neighbors"}}}}"#,
        "}"
    ])
    func missingHost(relationships: String) async throws {
        let event = HTTPFixture.coffee.dropLast() + relationships
        let client = DiscoveryClient { request in
            HTTPFixture.response(request, body: "{\"data\":\(event)}")
        }
        let huddl = try await client.detail(id: "coffee")
        #expect(huddl.hostName == nil)
        #expect(huddl.attributes.description == "Bring a mug and meet your neighbors.")
    }

    @Test("A removed or inaccessible huddl is an error, never stale details", arguments: [
        (404, "This huddl is no longer available."),
        (403, "Huddlz couldn’t load right now. Please try again."),
        (503, "Huddlz couldn’t load right now. Please try again.")
    ])
    func unavailableHuddl(status: Int, message: String) async {
        var attempts = 0
        let client = DiscoveryClient { request in
            attempts += 1
            if attempts == 1 { return HTTPFixture.response(request, body: "{}", status: status) }
            return HTTPFixture.response(request, body: "{\"data\":\(HTTPFixture.coffee)}")
        }
        await #expect {
            try await client.detail(id: "coffee")
        } throws: { error in
            error.localizedDescription == message
        }
        let retried = try? await client.detail(id: "coffee")
        #expect(retried?.title == "Coffee with neighbors")
    }
}

@MainActor
struct DiscoveryPlaceBehaviorTests {
    private static let staugustine = DiscoveryPlace(name: "St. Augustine, FL, USA", latitude: 29.9012,
                                                    longitude: -81.3124, timeZone: "America/New_York")

    @Test("Widening the distance searches farther from the same place")
    func wideningTheDistance() async {
        let discovery = DiscoveryStore(client: DiscoveryClient { request in
            let parameters = HTTPFixture.parameters(request)
            #expect(parameters["search_latitude"] == "29.9012")
            let events = parameters["distance_miles"] == "50" ? [HTTPFixture.coffee, HTTPFixture.hike] : [HTTPFixture.coffee]
            return HTTPFixture.response(request, body: HTTPFixture.page(events))
        })
        var query = DiscoveryQuery()
        query.place = Self.staugustine
        await discovery.search(query)
        #expect(discovery.huddlz.map(\.id) == ["coffee"])
        query.distanceMiles = 50
        await discovery.search(query)
        #expect(discovery.huddlz.map(\.id) == ["coffee", "hike"])
    }

    @Test("Clearing the place recovers from no nearby huddlz and keeps the search text")
    func clearingThePlace() async {
        let discovery = DiscoveryStore(client: DiscoveryClient { request in
            let parameters = HTTPFixture.parameters(request)
            #expect(parameters["query"] == "coffee")
            let nearby = parameters["search_latitude"] != nil
            #expect(nearby || parameters["distance_miles"] == nil)
            return HTTPFixture.response(request, body: HTTPFixture.page(nearby ? [] : [HTTPFixture.coffee]))
        })
        var query = DiscoveryQuery(text: "coffee")
        query.place = Self.staugustine
        await discovery.search(query)
        #expect(discovery.huddlz.isEmpty)
        #expect(discovery.errorMessage == nil)
        query.place = nil
        await discovery.search(query)
        #expect(discovery.huddlz.map(\.id) == ["coffee"])
    }

    @Test("Only in-person and hybrid huddlz with an announced address get a map", arguments: [
        ("in_person", "\"Juniper Café\"", "Juniper Café"),
        ("hybrid", "\"  Juniper Café \"", "Juniper Café"),
        ("virtual", "\"Juniper Café\"", nil),
        ("in_person", "null", nil),
        ("in_person", "\"   \"", nil)
    ] as [(String, String, String?)])
    func mapAddress(eventType: String, physicalLocation: String, expected: String?) async throws {
        let event = HTTPFixture.coffee.replacingOccurrences(of: "in_person", with: eventType)
            .replacingOccurrences(of: "\"Juniper Café\"", with: physicalLocation)
        let client = DiscoveryClient { request in HTTPFixture.response(request, body: "{\"data\":\(event)}") }
        let huddl = try await client.detail(id: "coffee")
        #expect(huddl.mapAddress == expected)
    }
}
