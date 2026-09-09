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

}
