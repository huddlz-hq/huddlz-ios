import Foundation
import Testing
@testable import Huddlz

@MainActor
struct AccountBehaviorTests {
    private static let user = #"{"id":"neighbor","email":"neighbor@example.com","display_name":"Our Neighbor"}"#
    private static let session = "{\"token\":\"fixture-token\",\"user\":\(user)}"

    @Test("Reset requests submit only the entered email to Huddlz")
    func resetRequestSubmitsEmail() async throws {
        var submitted = false
        let client = AccountClient { request in
            #expect(request.url?.absoluteString == "https://huddlz.com/api/auth/password_reset")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            let data = try #require(request.httpBody)
            let body = try JSONSerialization.jsonObject(with: data) as? [String: String]
            #expect(body == ["email": "neighbor+coffee@example.com"])
            submitted = true
            return HTTPFixture.response(request, body: "", status: 204)
        }
        try await client.requestPasswordReset(email: " neighbor+coffee@example.com \n")
        #expect(submitted)
    }

    @Test("A failed reset request explains the problem and can be retried", arguments: [
        (503, "Couldn’t request a reset link. Check your connection and try again."),
        (429, "Too many requests. Please try again later."),
        (-1, "Couldn’t request a reset link. Check your connection and try again.")
    ])
    func failedResetCanRetry(status: Int, message: String) async {
        var attempts = 0
        let reset = PasswordResetRequest(client: AccountClient { request in
            attempts += 1
            if attempts == 1 {
                if status < 0 { throw URLError(.notConnectedToInternet) }
                return HTTPFixture.response(request, body: "{}", status: status)
            }
            return HTTPFixture.response(request, body: "", status: 204)
        })
        #expect(!reset.canSend(email: "  "))
        await reset.send(email: "neighbor@example.com")
        #expect(reset.errorMessage == message)
        #expect(!reset.didRequestReset)
        #expect(reset.canSend(email: "neighbor@example.com"))
        await reset.send(email: "neighbor@example.com")
        #expect(reset.errorMessage == nil)
        #expect(reset.didRequestReset)
        #expect(!reset.canSend(email: "neighbor@example.com"))
        #expect(attempts == 2)
    }

    @Test("Sign-out removes the saved login before server revocation, even offline", arguments: [204, 401, 503, -1])
    func signOutClearsLocalSession(status: Int) async throws {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        var revoked = false
        let client = AccountClient { request in
            if request.url?.path == "/api/auth/sign_in" { return HTTPFixture.response(request, body: Self.session) }
            #expect(request.url?.path == "/api/auth/sign_out")
            #expect(request.httpMethod == "DELETE")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
            #expect(try await tokens.load() == nil)
            revoked = true
            if status < 0 { throw URLError(.notConnectedToInternet) }
            return HTTPFixture.response(request, body: "", status: status)
        }
        let account = AccountStore(client: client, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        await account.signOut()
        #expect(revoked)
        #expect(account.user == nil)
        #expect(!account.isBusy)
        #expect(try await tokens.load() == nil)
        if status == 503 || status < 0 {
            #expect(account.message == "Signed out on this device. Couldn’t end the session on the server.")
        } else { #expect(account.message == nil) }
        let reopened = AccountStore(client: client, tokens: tokens)
        await reopened.restore()
        #expect(reopened.user == nil)
        #expect(reopened.message == nil)
    }

    @Test("A failed session check keeps the saved login available for retry", arguments: [503, -1])
    func retrySessionCheck(status: Int) async throws {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        var checks = 0
        let client = AccountClient { request in
            if request.url?.path == "/api/auth/sign_in" { return HTTPFixture.response(request, body: Self.session) }
            checks += 1
            if checks == 1 {
                if status < 0 { throw URLError(.notConnectedToInternet) }
                return HTTPFixture.response(request, body: "{}", status: status)
            }
            return HTTPFixture.response(request, body: "{\"user\":\(Self.user)}")
        }
        let account = AccountStore(client: client, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        let reopened = AccountStore(client: client, tokens: tokens)
        await reopened.restore()
        #expect(reopened.user == nil)
        #expect(reopened.canRetrySession)
        #expect(reopened.message == "Couldn’t check your account. Check your connection and try again.")
        #expect(try await tokens.load() == "fixture-token")
        await reopened.restore()
        #expect(reopened.user?.email == "neighbor@example.com")
        #expect(!reopened.canRetrySession)
        #expect(reopened.message == nil)
    }

    @Test("Failed sign-in explains the problem and allows retry", arguments: [401, 429, 503, -1])
    func failedSignInCanRetry(status: Int) async throws {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        var attempts = 0
        let account = AccountStore(client: AccountClient { request in
            attempts += 1
            if attempts == 1 {
                if status < 0 { throw URLError(.notConnectedToInternet) }
                return HTTPFixture.response(request, body: "{}", status: status)
            }
            return HTTPFixture.response(request, body: Self.session)
        }, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        #expect(account.user == nil)
        #expect(!account.isBusy)
        #expect(try await tokens.load() == nil)
        let messages = [401: "The email or password is incorrect. Try again.",
                        429: "Too many sign-in attempts. Please try again later."]
        #expect(account.message == (messages[status] ?? "Couldn’t sign in. Check your connection and try again."))
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        #expect(account.user?.email == "neighbor@example.com")
        #expect(account.message == nil)
    }

    @Test("An expired session asks for sign-in and is not restored again")
    func expiredSession() async throws {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        var checks = 0
        let client = AccountClient { request in
            if request.url?.path == "/api/auth/sign_in" { return HTTPFixture.response(request, body: Self.session) }
            checks += 1
            return HTTPFixture.response(request, body: "{}", status: 401)
        }
        let account = AccountStore(client: client, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        await account.restore()
        #expect(account.user == nil)
        #expect(account.message == "Your session has expired. Please sign in again.")
        #expect(try await tokens.load() == nil)
        let reopened = AccountStore(client: client, tokens: tokens)
        await reopened.restore()
        #expect(reopened.user == nil)
        #expect(checks == 1)
    }

    @Test("Sign-in sends credentials and restores the account using only its saved token")
    func credentialsAndSavedSession() async throws {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        var checkedSession = false
        let client = AccountClient { request in
            #expect(request.url?.scheme == "https")
            #expect(request.url?.host == "huddlz.com")
            if request.url?.path == "/api/auth/sign_in" {
                #expect(request.httpMethod == "POST")
                #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
                let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: String]
                #expect(body == ["email": "neighbor@example.com", "password": "p&ss word"])
                return HTTPFixture.response(request, body: Self.session)
            }
            #expect(request.url?.path == "/api/auth/me")
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
            #expect(request.httpBody == nil)
            checkedSession = true
            return HTTPFixture.response(request, body: "{\"user\":\(Self.user)}")
        }
        let account = AccountStore(client: client, tokens: tokens)
        await account.signIn(email: " neighbor@example.com ", password: "p&ss word")
        #expect(account.user?.email == "neighbor@example.com")
        #expect(try await tokens.load() == "fixture-token")
        let reopened = AccountStore(client: client, tokens: tokens)
        await reopened.restore()
        #expect(checkedSession)
        #expect(reopened.user?.displayName == "Our Neighbor")
    }

    @Test("Deleting the account confirms with the password and forgets the saved session")
    func deletingTheAccountForgetsTheSession() async throws {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        var deleted = false
        let client = AccountClient { request in
            if request.url?.path == "/api/auth/sign_in" { return HTTPFixture.response(request, body: Self.session) }
            #expect(request.url?.absoluteString == "https://huddlz.com/api/auth/account")
            #expect(request.httpMethod == "DELETE")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
            let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: String]
            #expect(body == ["password": "sample-password"])
            deleted = true
            return HTTPFixture.response(request, body: "", status: 204)
        }
        let account = AccountStore(client: client, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        let refusal = await account.deleteAccount(password: "sample-password")
        #expect(deleted)
        #expect(refusal == nil)
        #expect(account.user == nil)
        #expect(account.message == "Your account was deleted.")
        #expect(try await tokens.load() == nil)
        let reopened = AccountStore(client: client, tokens: tokens)
        await reopened.restore()
        #expect(reopened.user == nil)
    }

    @Test("A refused or failed deletion keeps the account signed in", arguments: [422, 429, 503, -1])
    func refusedDeletionKeepsTheAccount(status: Int) async throws {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        let client = AccountClient { request in
            if request.url?.path == "/api/auth/sign_in" { return HTTPFixture.response(request, body: Self.session) }
            if status < 0 { throw URLError(.notConnectedToInternet) }
            let body = #"{"errors":[{"field":"password","message":"That password isn’t right."}]}"#
            return HTTPFixture.response(request, body: body, status: status)
        }
        let account = AccountStore(client: client, tokens: tokens)
        await account.signIn(email: "neighbor@example.com", password: "sample-password")
        let refusal = await account.deleteAccount(password: "wrong-password")
        let messages = [422: "That password isn’t right.", 429: "Too many attempts. Please try again later."]
        #expect(refusal == (messages[status] ?? "Couldn’t delete your account. Check your connection and try again."))
        #expect(account.user?.email == "neighbor@example.com")
        #expect(!account.isBusy)
        #expect(try await tokens.load() == "fixture-token")
    }
}
