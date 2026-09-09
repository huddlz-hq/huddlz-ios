import Foundation
import Testing
@testable import Huddlz

@MainActor
struct JoiningBehaviorTests {
    private static let session = #"{"token":"fixture-token","user":{"id":"neighbor","email":"neighbor@example.com"}}"#

    @Test("Unreadable joining details never produce an actionable link", arguments: [
        #"{"data":{"id":"coffee","attributes":{"visible_virtual_link":"ftp://example.com/room"}}}"#,
        #"{"data":{"id":"coffee","attributes":{"visible_virtual_link":"/room"}}}"#,
        #"{"data":{"id":"other","attributes":{"visible_virtual_link":"https://example.com/room"}}}"#
    ])
    func unreadableJoiningDetailsAreAnError(body: String) async throws {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        let account = AccountStore(client: AccountClient { request in
            HTTPFixture.response(request, body: request.url?.path == "/api/auth/sign_in" ? Self.session : body)
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        await #expect(throws: (any Error).self) { try await account.joiningLink(huddlID: "coffee") }
        #expect(account.user?.id == "neighbor")
    }

    @Test("Signing out discards an authenticated joining link response already in flight")
    func signingOutDiscardsPendingJoining() async throws {
        let pending = PendingHTTPResponse()
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        let account = AccountStore(client: AccountClient { request in
            if request.url?.path == "/api/json/huddlz/coffee" {
                #expect(request.httpMethod == "GET")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
                #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.api+json")
                #expect(HTTPFixture.parameters(request)["fields[huddl]"] == "visible_virtual_link")
                return try await pending.fetch(request)
            }
            return HTTPFixture.response(request, body: Self.session)
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        let loading = Task { try await account.joiningLink(huddlID: "coffee") }
        await pending.waitUntilRequested()
        await account.signOut()
        pending.finish(body: #"{"data":{"id":"coffee","attributes":{"visible_virtual_link":"https://example.com/huddl-room"}}}"#)
        await #expect(throws: CancellationError.self) { try await loading.value }
        #expect(account.user == nil)
    }

}
