import Foundation
import Testing
@testable import Huddlz

@MainActor
struct AttendanceBehaviorTests {
    private static let session = #"{"token":"fixture-token","user":{"id":"neighbor","email":"neighbor@example.com"}}"#

    @Test("Unreadable RSVP status is an error, never an absent RSVP", arguments: [
        #"{"data":{"id":"coffee","attributes":{"attendance_state":null}}}"#,
        #"{"data":{"id":"coffee","attributes":{}}}"#,
        #"{"data":{"id":"coffee","attributes":{"attendance_state":"unexpected"}}}"#,
        #"{"data":{"id":"other","attributes":{"attendance_state":"confirmed"}}}"#
    ])
    func unreadableStatusDoesNotInventAnRSVP(body: String) async throws {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        let account = AccountStore(client: AccountClient { request in
            HTTPFixture.response(request, body: request.url?.path == "/api/auth/sign_in" ? Self.session : body)
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        await #expect(throws: (any Error).self) { try await account.attendance(huddlID: "coffee") }
        #expect(account.user?.id == "neighbor")
        #expect(account.message == nil)
    }

    @Test("Signing out discards an authenticated RSVP response already in flight")
    func signingOutDiscardsPendingAttendance() async throws {
        let pending = PendingHTTPResponse()
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        let account = AccountStore(client: AccountClient { request in
            if request.url?.path == "/api/json/huddlz/coffee" {
                #expect(request.httpMethod == "GET")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
                #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.api+json")
                #expect(HTTPFixture.parameters(request)["fields[huddl]"] == "attendance_state")
                return try await pending.fetch(request)
            }
            return HTTPFixture.response(request, body: Self.session)
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        let loading = Task { try await account.attendance(huddlID: "coffee") }
        await pending.waitUntilRequested()
        await account.signOut()
        pending.finish(body: #"{"data":{"id":"coffee","attributes":{"attendance_state":"confirmed"}}}"#)
        await #expect(throws: CancellationError.self) { try await loading.value }
        #expect(account.user == nil)
    }

    private static func attendance(_ state: String) -> String {
        #"{"data":{"id":"coffee","attributes":{"attendance_state":"\#(state)"}}}"#
    }

    @Test("Details show the signed-in person's current RSVP", arguments: [
        ("confirmed", AttendanceState.confirmed),
        ("waitlisted", AttendanceState.waitlisted),
        ("none", AttendanceState.none)
    ])
    func currentRSVP(body: String, expected: AttendanceState) async {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        let account = AccountStore(client: AccountClient { request in
            HTTPFixture.response(request, body: request.url?.path == "/api/json/huddlz/coffee" ? Self.attendance(body) : Self.session)
        }, tokens: tokens)
        let status = HuddlAttendanceStore()
        await status.load(huddlID: "coffee", account: account)
        #expect(status.attendance == nil)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        await status.load(huddlID: "coffee", account: account)
        #expect(status.attendance == expected)
        #expect(status.loadedUserID == "neighbor")
    }

    @Test("A failed RSVP check makes no claim and can be retried", arguments: [503, -1])
    func failedStatusCanRetry(status code: Int) async {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        var attempts = 0
        let account = AccountStore(client: AccountClient { request in
            guard request.url?.path == "/api/json/huddlz/coffee" else { return HTTPFixture.response(request, body: Self.session) }
            attempts += 1
            if attempts == 1 {
                if code < 0 { throw URLError(.notConnectedToInternet) }
                return HTTPFixture.response(request, body: "{}", status: code)
            }
            return HTTPFixture.response(request, body: Self.attendance("confirmed"))
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        let status = HuddlAttendanceStore()
        await status.load(huddlID: "coffee", account: account)
        #expect(status.loadFailed)
        #expect(status.attendance == nil)
        await status.load(huddlID: "coffee", account: account)
        #expect(!status.loadFailed)
        #expect(status.attendance == .confirmed)
    }

    @Test("Checking again shows an RSVP changed elsewhere")
    func changedElsewhere() async {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        var server = "confirmed"
        let account = AccountStore(client: AccountClient { request in
            HTTPFixture.response(request, body: request.url?.path == "/api/json/huddlz/coffee" ? Self.attendance(server) : Self.session)
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        let status = HuddlAttendanceStore()
        await status.load(huddlID: "coffee", account: account)
        #expect(status.attendance == .confirmed)
        server = "none"
        await status.load(huddlID: "coffee", account: account)
        #expect(status.attendance == AttendanceState.none)
    }

}
