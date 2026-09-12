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

    private actor Requests {
        private(set) var urls: [URL] = []
        func add(_ url: URL) { urls.append(url) }
    }
}
