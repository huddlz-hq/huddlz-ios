import Foundation
import Testing
@testable import Huddlz

@MainActor
struct ModerationBehaviorTests {
    private static let session = #"{"token":"fixture-token","user":{"id":"neighbor","email":"neighbor@example.com"}}"#

    private func signedIn(_ respond: @escaping (URLRequest) async throws -> (Data, URLResponse)?) async -> (AccountStore, SessionTokenStore) {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        let account = AccountStore(client: AccountClient { request in
            if let response = try await respond(request) { return response }
            return HTTPFixture.response(request, body: Self.session)
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        return (account, tokens)
    }

    @Test("Reporting an organizer names the huddl and the reason, never an account")
    func reportNamesHuddlAndReason() async throws {
        var sent: [String: Any]?
        let (account, tokens) = await signedIn { request in
            guard request.url?.path == "/api/json/account_reports/organizer" else { return nil }
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/vnd.api+json")
            let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
            sent = body["data"] as? [String: Any]
            return HTTPFixture.response(request, body: "", status: 201)
        }
        defer { Task { try? await tokens.clear() } }
        try await account.reportOrganizer(huddlID: "coffee", reason: .spam, details: "  Coin listings  ")
        #expect(sent?["huddl_id"] as? String == "coffee")
        #expect(sent?["reason"] as? String == "spam")
        #expect(sent?["details"] as? String == "Coin listings")
        #expect(sent?["reported_user_id"] == nil)
    }

    @Test("A report the server turns down explains why")
    func refusedReportExplains() async throws {
        let (account, tokens) = await signedIn { request in
            switch request.url?.path {
            case "/api/json/account_reports/organizer":
                return HTTPFixture.response(request, body: #"{"errors":[{"detail":"Say what's wrong: spam or advertising, or other."}]}"#, status: 400)
            default: return nil
            }
        }
        defer { Task { try? await tokens.clear() } }
        let error = await #expect(throws: ModerationError.self) {
            try await account.reportOrganizer(huddlID: "coffee", reason: .other, details: "")
        }
        #expect(error?.message == "Say what's wrong: spam or advertising, or other.")
        #expect(account.user?.id == "neighbor")
    }

    @Test("Blocking an organizer asks lists to drop their huddlz")
    func blockingRefreshesLists() async throws {
        var blockedHuddl: String?
        let (account, tokens) = await signedIn { request in
            guard request.url?.path == "/api/json/blocks/organizer" else { return nil }
            let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
            let data = try #require(body["data"] as? [String: Any])
            #expect(data["type"] as? String == "user_block")
            blockedHuddl = (data["attributes"] as? [String: String])?["huddl_id"]
            return HTTPFixture.response(request, body: #"{"data":{"type":"user_block","id":"b1","attributes":{}}}"#, status: 201)
        }
        defer { Task { try? await tokens.clear() } }
        let before = account.blockRevision
        try await account.blockOrganizer(huddlID: "coffee")
        #expect(blockedHuddl == "coffee")
        #expect(account.blockRevision != before)
    }

    @Test("A block refused for your own huddl changes nothing")
    func refusedBlockKeepsLists() async throws {
        let (account, tokens) = await signedIn { request in
            guard request.url?.path == "/api/json/blocks/organizer" else { return nil }
            return HTTPFixture.response(request, body: #"{"errors":[{"detail":"You organize this huddl."}]}"#, status: 400)
        }
        defer { Task { try? await tokens.clear() } }
        let before = account.blockRevision
        let error = await #expect(throws: ModerationError.self) { try await account.blockOrganizer(huddlID: "coffee") }
        #expect(error?.message == "You organize this huddl.")
        #expect(account.blockRevision == before)
    }

    @Test("An expired session while blocking returns the person to signed-out browsing")
    func expiredSessionWhileBlocking() async throws {
        let (account, tokens) = await signedIn { request in
            guard request.url?.path == "/api/json/blocks/organizer" else { return nil }
            return HTTPFixture.response(request, body: "{}", status: 401)
        }
        defer { Task { try? await tokens.clear() } }
        let error = await #expect(throws: ModerationError.self) { try await account.blockOrganizer(huddlID: "coffee") }
        #expect(error?.message == "Your session expired. Please sign in again.")
        #expect(account.user == nil)
        #expect(try await tokens.load() == nil)
    }

    @Test("Blocked organizers are listed by name and can be unblocked")
    func listAndUnblock() async throws {
        var deleted: String?
        let (account, tokens) = await signedIn { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/json/blocks"):
                return HTTPFixture.response(request, body: #"{"data":[{"type":"user_block","id":"b1","attributes":{"blocked_user_name":"Crypto Kings Promo"}}]}"#)
            case ("DELETE", "/api/json/blocks/b1"):
                deleted = "b1"
                return HTTPFixture.response(request, body: "", status: 204)
            default: return nil
            }
        }
        defer { Task { try? await tokens.clear() } }
        let people = try await account.blockedPeople()
        #expect(people == [BlockedPerson(id: "b1", name: "Crypto Kings Promo")])
        let before = account.blockRevision
        try await account.unblock(people[0])
        #expect(deleted == "b1")
        #expect(account.blockRevision != before)
    }

    @Test("Signed-in discovery searches as the person, and an expired session still browses")
    func discoverySearchesAsThePerson() async throws {
        var authorizations: [String?] = []
        let discovery = DiscoveryStore(client: DiscoveryClient { request in
            let authorization = request.value(forHTTPHeaderField: "Authorization")
            authorizations.append(authorization)
            if authorization == "Bearer expired" { return HTTPFixture.response(request, body: "{}", status: 401) }
            return HTTPFixture.response(request, body: HTTPFixture.page([HTTPFixture.coffee]))
        })
        await discovery.load(DiscoveryQuery(), token: "fixture-token")
        #expect(authorizations == ["Bearer fixture-token"])
        await discovery.load(DiscoveryQuery(), token: "expired")
        #expect(authorizations == ["Bearer fixture-token", "Bearer expired", nil])
        #expect(discovery.huddlz.map(\.id) == ["coffee"])
    }
}
