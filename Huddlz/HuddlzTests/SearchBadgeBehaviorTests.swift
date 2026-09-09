import Foundation
import Testing
@testable import Huddlz

@MainActor
struct SearchBadgeBehaviorTests {
    private static let session = #"{"token":"fixture-token","user":{"id":"neighbor","email":"neighbor@example.com"}}"#

    @Test("A late badge response cannot replace the badges for the current cards")
    func newerCardsWinOverALateResponse() async throws {
        let pending = PendingHTTPResponse()
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        let account = AccountStore(client: AccountClient { request in
            if request.url?.path == "/api/json/huddlz" {
                let ids = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                    .filter { $0.name == "filter[id][in][]" }.compactMap(\.value)
                if ids == ["coffee"] { return try await pending.fetch(request) }
                return HTTPFixture.response(request, body: #"{"data":[{"id":"walk","attributes":{"attendance_state":"waitlisted"}}]}"#)
            }
            return HTTPFixture.response(request, body: Self.session)
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        let badges = SearchBadgeStore()
        let older = Task { await badges.load(huddlIDs: ["coffee"], account: account) }
        await pending.waitUntilRequested()
        await badges.load(huddlIDs: ["walk"], account: account)
        pending.finish(body: #"{"data":[{"id":"coffee","attributes":{"attendance_state":"confirmed"}}]}"#)
        await older.value
        #expect(badges.attendance(for: "walk", userID: account.user?.id) == .waitlisted)
        #expect(badges.attendance(for: "coffee", userID: account.user?.id) == nil)
    }

    @Test("A failed badge refresh removes stale badges and a later retry recovers")
    func failedBadgesCanBeRetried() async {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        var attempts = 0
        let account = AccountStore(client: AccountClient { request in
            guard request.url?.path == "/api/json/huddlz" else { return HTTPFixture.response(request, body: Self.session) }
            attempts += 1
            if attempts == 2 { return HTTPFixture.response(request, body: "{}", status: 503) }
            let state = attempts == 1 ? "confirmed" : "waitlisted"
            return HTTPFixture.response(request, body: "{\"data\":[{\"id\":\"coffee\",\"attributes\":{\"attendance_state\":\"\(state)\"}}]}")
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        let badges = SearchBadgeStore()
        await badges.load(huddlIDs: ["coffee"], account: account)
        #expect(badges.attendance(for: "coffee", userID: account.user?.id) == .confirmed)
        await badges.load(huddlIDs: ["coffee"], account: account)
        #expect(badges.attendance(for: "coffee", userID: account.user?.id) == nil)
        #expect(account.user?.id == "neighbor")
        await badges.load(huddlIDs: ["coffee"], account: account)
        #expect(badges.attendance(for: "coffee", userID: account.user?.id) == .waitlisted)
    }


    @Test("Card statuses load in bounded authenticated batches and ignore unrelated results")
    func cardStatusesUseBatches() async throws {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        var batches: [Set<String>] = []
        let account = AccountStore(client: AccountClient { request in
            guard request.url?.path == "/api/json/huddlz" else { return HTTPFixture.response(request, body: Self.session) }
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
            let parameters = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            let ids = Set(parameters.filter { $0.name == "filter[id][in][]" }.compactMap(\.value))
            #expect(parameters.first { $0.name == "date_filter" }?.value == "all")
            #expect(parameters.first { $0.name == "page[limit]" }?.value == "20")
            #expect(parameters.first { $0.name == "fields[huddl]" }?.value == "attendance_state")
            batches.append(ids)
            let resources = (ids.sorted() + ["unrelated"]).map {
                "{\"id\":\"\($0)\",\"attributes\":{\"attendance_state\":\"confirmed\"}}"
            }.joined(separator: ",")
            return HTTPFixture.response(request, body: "{\"data\":[\(resources)]}")
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        let ids = Set((1...21).map { "huddl-\($0)" })
        let states = try await account.attendances(huddlIDs: ids)
        #expect(Set(states.keys) == ids)
        #expect(states.values.allSatisfy { $0 == .confirmed })
        #expect(batches.count == 2)
        #expect(batches.map(\.count).sorted() == [1, 20])
        #expect(batches.reduce(into: Set<String>()) { $0.formUnion($1) } == ids)
    }

}
