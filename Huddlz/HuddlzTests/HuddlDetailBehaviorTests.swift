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
