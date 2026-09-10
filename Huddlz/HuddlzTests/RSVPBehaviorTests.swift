import Foundation
import Testing
@testable import Huddlz

@MainActor
struct RSVPBehaviorTests {
    private static let session = #"{"token":"fixture-token","user":{"id":"neighbor","email":"neighbor@example.com"}}"#

    @Test("Refreshing the same session preserves a pending RSVP")
    func refreshingSameSessionPreservesRSVP() async throws {
        let pending = PendingHTTPResponse()
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        let account = AccountStore(client: AccountClient { request in
            if request.url?.path == "/api/json/huddlz/coffee/rsvp" { return try await pending.fetch(request) }
            return HTTPFixture.response(request, body: Self.session)
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        let changing = Task { try await account.changeAttendance(huddlID: "coffee", action: .reserve) }
        await pending.waitUntilRequested()
        await account.restore()
        pending.finish(body: #"{"data":{"id":"coffee","attributes":{"attendance_state":"confirmed"}}}"#)
        #expect(try await changing.value == .confirmed)
        #expect(account.user?.id == "neighbor")
    }

    @Test("Old RSVP responses cannot affect a new sign-in for the same person", arguments: [200, 401])
    func oldResponsePreservesNewSession(responseStatus: Int) async throws {
        let pending = PendingHTTPResponse()
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        let account = AccountStore(client: AccountClient { request in
            if request.url?.path == "/api/json/huddlz/coffee/rsvp" { return try await pending.fetch(request) }
            return HTTPFixture.response(request, body: Self.session)
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        let changing = Task { try await account.changeAttendance(huddlID: "coffee", action: .reserve) }
        await pending.waitUntilRequested()
        await account.signOut()
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        pending.finish(body: #"{"data":{"id":"coffee","attributes":{"attendance_state":"confirmed"}}}"#, status: responseStatus)
        await #expect(throws: CancellationError.self) { try await changing.value }
        #expect(account.user?.id == "neighbor")
        #expect(try await tokens.load() == "fixture-token")
    }

    @Test("A late status read cannot undo a successful RSVP")
    func lateStatusCannotUndoRSVP() async throws {
        let pendingRead = PendingHTTPResponse()
        let pendingChange = PendingHTTPResponse()
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        let account = AccountStore(client: AccountClient { request in
            switch request.url?.path {
            case "/api/json/huddlz/coffee": return try await pendingRead.fetch(request)
            case "/api/json/huddlz/coffee/rsvp": return try await pendingChange.fetch(request)
            default: return HTTPFixture.response(request, body: Self.session)
            }
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        let status = HuddlAttendanceStore()
        let changing = Task { await status.change(huddlID: "coffee", action: .reserve, account: account) }
        await pendingChange.waitUntilRequested()
        let reading = Task { await status.load(huddlID: "coffee", account: account) }
        await pendingRead.waitUntilRequested()
        pendingChange.finish(body: #"{"data":{"id":"coffee","attributes":{"attendance_state":"confirmed"}}}"#)
        await changing.value
        #expect(status.attendance == .confirmed)
        pendingRead.finish(body: #"{"data":{"id":"coffee","attributes":{"attendance_state":"none"}}}"#)
        await reading.value
        #expect(status.attendance == .confirmed)
    }

    @Test("Signing out discards pending RSVP and cancellation responses", arguments: [RSVPAction.reserve, .cancel])
    func signOutDiscardsPendingChanges(action: RSVPAction) async throws {
        let pending = PendingHTTPResponse()
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        let account = AccountStore(client: AccountClient { request in
            if request.url?.path == "/api/json/huddlz/coffee/\(action.rawValue)" {
                #expect(request.httpMethod == "PATCH")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
                #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/vnd.api+json")
                #expect(HTTPFixture.parameters(request)["fields[huddl]"] == "attendance_state")
                let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
                let data = try #require(body["data"] as? [String: Any])
                #expect(data["id"] as? String == "coffee")
                #expect(data["type"] as? String == "huddl")
                #expect((data["attributes"] as? [String: String])?.isEmpty == true)
                return try await pending.fetch(request)
            }
            return HTTPFixture.response(request, body: Self.session)
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        let changing = Task { try await account.changeAttendance(huddlID: "coffee", action: action) }
        await pending.waitUntilRequested()
        await account.signOut()
        pending.finish(body: #"{"data":{"id":"coffee","attributes":{"attendance_state":"confirmed"}}}"#)
        await #expect(throws: CancellationError.self) { try await changing.value }
        #expect(account.user == nil)
    }

    @Test("An expired RSVP session returns the person to signed-out browsing")
    func expiredSessionRequiresSignIn() async throws {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        let account = AccountStore(client: AccountClient { request in
            if request.url?.path == "/api/auth/sign_in" { return HTTPFixture.response(request, body: Self.session) }
            return HTTPFixture.response(request, body: "{}", status: 401)
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        await #expect(throws: (any Error).self) { try await account.changeAttendance(huddlID: "coffee", action: .reserve) }
        #expect(account.user == nil)
        #expect(try await tokens.load() == nil)
    }
}
