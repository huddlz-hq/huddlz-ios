import Foundation
import Testing
@testable import Huddlz

@MainActor
struct GroupsBehaviorTests {
    private static let session = #"{"token":"fixture-token","user":{"id":"neighbor","email":"neighbor@example.com"}}"#
    private static let neighbors = #"{"type":"group","id":"neighbors","attributes":{"name":"Juniper Neighbors","location":"Austin, TX"}}"#

    @Test("A groups response that arrives after signing out cannot fill the list")
    func lateGroupsCannotOutliveTheAccount() async throws {
        let pending = PendingHTTPResponse()
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        let account = AccountStore(client: AccountClient { request in
            switch request.url?.path {
            case "/api/json/groups/mine": return try await pending.fetch(request)
            case "/api/auth/sign_out": return HTTPFixture.response(request, body: "", status: 204)
            default: return HTTPFixture.response(request, body: Self.session)
            }
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        let store = GroupsStore()
        let loading = Task { await store.load(account: account) }
        await pending.waitUntilRequested()
        await account.signOut()
        pending.finish(body: "{\"data\":[\(Self.neighbors)]}")
        await loading.value
        #expect(store.groups.isEmpty)
        #expect(store.loadedUserID == nil)
        #expect(!store.loadFailed)
    }

    @Test("Loading more follows only the API's own next link for the member's groups")
    func loadMoreRejectsForeignLinks() async {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        let requested = Requests()
        let account = AccountStore(client: AccountClient { request in
            await requested.add(request.url!)
            guard request.url?.path == "/api/json/groups/mine" else { return HTTPFixture.response(request, body: Self.session) }
            let next = "https://example.com/api/json/groups/mine?page%5Boffset%5D=20"
            return HTTPFixture.response(request, body: "{\"data\":[\(Self.neighbors)],\"links\":{\"next\":\"\(next)\"}}")
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        let store = GroupsStore()
        await store.load(account: account)
        #expect(store.groups.map(\.id) == ["neighbors"])
        #expect(store.nextPage != nil)
        await store.loadMore(account: account)
        #expect(store.moreFailed)
        #expect(store.groups.map(\.id) == ["neighbors"])
        let hosts = await requested.urls.compactMap(\.host)
        #expect(!hosts.contains("example.com"))
    }

    @Test("Having no groups loads without an error")
    func noGroups() async {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        let account = AccountStore(client: AccountClient { request in
            guard request.url?.path == "/api/json/groups/mine" else { return HTTPFixture.response(request, body: Self.session) }
            return HTTPFixture.response(request, body: #"{"data":[],"links":{"next":null}}"#)
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        let store = GroupsStore()
        await store.load(account: account)
        #expect(store.groups.isEmpty)
        #expect(!store.loadFailed)
        #expect(store.nextPage == nil)
    }

    @Test("A failed groups load can be retried", arguments: [503, -1])
    func failedGroupsCanRetry(status: Int) async {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        var attempts = 0
        let account = AccountStore(client: AccountClient { request in
            guard request.url?.path == "/api/json/groups/mine" else { return HTTPFixture.response(request, body: Self.session) }
            attempts += 1
            if attempts == 1 {
                if status < 0 { throw URLError(.notConnectedToInternet) }
                return HTTPFixture.response(request, body: "{}", status: status)
            }
            return HTTPFixture.response(request, body: "{\"data\":[\(Self.neighbors)]}")
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        let store = GroupsStore()
        await store.load(account: account)
        #expect(store.loadFailed)
        #expect(store.groups.isEmpty)
        await store.load(account: account)
        #expect(!store.loadFailed)
        #expect(store.groups.map(\.id) == ["neighbors"])
    }

    @Test("Loading more adds the next page of groups and stops at the end")
    func loadMoreAddsTheNextPage() async {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        let runners = #"{"type":"group","id":"runners","attributes":{"name":"River Runners","location":"Portland, OR"}}"#
        let next = "https://huddlz.com/api/json/groups/mine?page%5Blimit%5D=20&page%5Boffset%5D=20"
        let account = AccountStore(client: AccountClient { request in
            guard request.url?.path == "/api/json/groups/mine" else { return HTTPFixture.response(request, body: Self.session) }
            if HTTPFixture.parameters(request)["page[offset]"] == "20" {
                return HTTPFixture.response(request, body: "{\"data\":[\(Self.neighbors),\(runners)],\"links\":{\"next\":null}}")
            }
            return HTTPFixture.response(request, body: "{\"data\":[\(Self.neighbors)],\"links\":{\"next\":\"\(next)\"}}")
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        let store = GroupsStore()
        await store.load(account: account)
        #expect(store.groups.map(\.id) == ["neighbors"])
        await store.loadMore(account: account)
        #expect(store.groups.map(\.id) == ["neighbors", "runners"])
        #expect(store.nextPage == nil)
        #expect(!store.moreFailed)
    }

    @Test("Signing out and in as someone else shows only the new member's groups")
    func groupsFollowTheSignedInMember() async {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        let runners = #"{"type":"group","id":"runners","attributes":{"name":"River Runners","location":"Portland, OR"}}"#
        var signIns = 0
        let account = AccountStore(client: AccountClient { request in
            switch request.url?.path {
            case "/api/json/groups/mine":
                return HTTPFixture.response(request, body: "{\"data\":[\(signIns == 1 ? Self.neighbors : runners)]}")
            case "/api/auth/sign_out":
                return HTTPFixture.response(request, body: "", status: 204)
            case "/api/auth/sign_in":
                signIns += 1
                return HTTPFixture.response(request, body: Self.session)
            default:
                return HTTPFixture.response(request, body: Self.session)
            }
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        let store = GroupsStore()
        await store.load(account: account)
        #expect(store.groups.map(\.id) == ["neighbors"])
        await account.signOut()
        await store.load(account: account)
        #expect(store.groups.isEmpty)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        await store.load(account: account)
        #expect(store.groups.map(\.id) == ["runners"])
    }

    private actor Requests {
        private(set) var urls: [URL] = []
        func add(_ url: URL) { urls.append(url) }
    }
}
