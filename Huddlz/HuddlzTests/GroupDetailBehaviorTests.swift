import Foundation
import Testing
@testable import Huddlz

@MainActor
struct GroupDetailBehaviorTests {
    private static let group = #"{"data":{"type":"group","id":"neighbors","attributes":{"name":"Juniper Neighbors","description":"Neighbors who love getting outside.","location":"Austin, TX"}}}"#
    private static let next = "https://huddlz.com/api/json/huddlz/by_group?group_id=neighbors&page%5Bafter%5D=coffee"

    private static func client(group: @escaping () -> (Int, String),
                               huddlz: @escaping () -> (Int, String),
                               more: @escaping () -> (Int, String) = { (200, HTTPFixture.page([])) }) -> DiscoveryClient {
        DiscoveryClient { request in
            let reply: (Int, String)
            switch request.url?.path {
            case "/api/json/groups/neighbors": reply = group()
            case "/api/json/huddlz/by_group":
                reply = HTTPFixture.parameters(request)["page[after]"] == nil ? huddlz() : more()
            default: reply = (404, "{}")
            }
            return HTTPFixture.response(request, body: reply.1, status: reply.0)
        }
    }

    @Test("A group with no upcoming huddlz loads with an empty list")
    func emptyGroup() async {
        let store = GroupDetailStore(id: "neighbors", client: Self.client(group: { (200, Self.group) },
                                                                            huddlz: { (200, HTTPFixture.page([])) }))
        await store.load()
        #expect(store.group?.attributes.description == "Neighbors who love getting outside.")
        #expect(store.hasLoadedHuddlz)
        #expect(store.huddlz.isEmpty)
        #expect(store.huddlzError == nil)
    }

    @Test("A removed or unavailable group explains why and can be retried", arguments: [
        (404, "This group is no longer available."),
        (503, "The group couldn’t load right now. Please try again.")
    ])
    func unavailableGroup(status: Int, message: String) async {
        var attempts = 0
        let store = GroupDetailStore(id: "neighbors", client: Self.client(group: {
            attempts += 1
            return attempts == 1 ? (status, "{}") : (200, Self.group)
        }, huddlz: { (200, HTTPFixture.page([HTTPFixture.coffee])) }))
        await store.load()
        #expect(store.errorMessage == message)
        #expect(store.group == nil)
        #expect(store.huddlz.isEmpty)
        await store.load()
        #expect(store.errorMessage == nil)
        #expect(store.group?.attributes.name == "Juniper Neighbors")
        #expect(store.huddlz.map(\.id) == ["coffee"])
    }

    @Test("Failed huddlz keep the group visible and can be retried")
    func failedHuddlzCanRetry() async {
        var attempts = 0
        let store = GroupDetailStore(id: "neighbors", client: Self.client(group: { (200, Self.group) }, huddlz: {
            attempts += 1
            return attempts == 1 ? (503, "{}") : (200, HTTPFixture.page([HTTPFixture.coffee]))
        }))
        await store.load()
        #expect(store.group != nil)
        #expect(store.huddlzError != nil)
        #expect(!store.hasLoadedHuddlz)
        await store.load()
        #expect(store.huddlzError == nil)
        #expect(store.huddlz.map(\.id) == ["coffee"])
    }

    @Test("A failed next batch keeps the group and cards, and a retry adds the rest without duplicates")
    func moreHuddlzCanRetry() async {
        var attempts = 0
        let store = GroupDetailStore(id: "neighbors", client: Self.client(group: { (200, Self.group) }, huddlz: {
            (200, HTTPFixture.page([HTTPFixture.coffee], next: Self.next))
        }, more: {
            attempts += 1
            return attempts == 1 ? (503, "{}") : (200, HTTPFixture.page([HTTPFixture.coffee, HTTPFixture.hike]))
        }))
        await store.load()
        #expect(store.nextPage != nil)
        await store.loadMore()
        #expect(store.moreError)
        #expect(store.huddlz.map(\.id) == ["coffee"])
        #expect(store.group != nil)
        await store.loadMore()
        #expect(!store.moreError)
        #expect(store.huddlz.map(\.id) == ["coffee", "hike"])
        #expect(store.nextPage == nil)
    }
}
