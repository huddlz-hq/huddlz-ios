import Foundation
import Testing
@testable import Huddlz

@MainActor
struct RegistrationBehaviorTests {
    private static let user = #"{"id":"neighbor","email":"neighbor@example.com","display_name":"Our Neighbor"}"#
    private static let session = "{\"token\":\"fixture-token\",\"user\":\(user)}"

    @Test("Failed registration explains the problem without saving a session and allows retry", arguments: [422, 0, 429, 503, -1])
    func failedRegistrationCanRetry(status: Int) async throws {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        var attempts = 0
        let client = AccountClient { request in
            #expect(request.url?.path == "/api/auth/register")
            attempts += 1
            if attempts == 1 {
                let data = try #require(request.httpBody)
                let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
                #expect(body["password"] as? String == "sample-password")
                #expect(body["password_confirmation"] as? String == "mismatched-confirmation")
                if status < 0 { throw URLError(.notConnectedToInternet) }
                let responseBody = status == 422 ? #"{"errors":[{"field":"password","message":"Bread Crumbs:\nargument password is required"}]}"# : "unreadable response"
                return HTTPFixture.response(request, body: responseBody, status: status == 0 ? 422 : status)
            }
            return HTTPFixture.response(request, body: Self.session, status: 201)
        }
        let account = AccountStore(client: client, tokens: tokens)
        await account.register(displayName: "Our Neighbor", email: "neighbor@example.com",
                               password: "sample-password", confirmation: "mismatched-confirmation", legalAcceptance: true)
        #expect(account.user == nil)
        #expect(!account.isBusy)
        #expect(try await tokens.load() == nil)
        let expected = status == 429 ? "Too many attempts. Please try again later." :
            (status == 422 || status == 0 ? "Couldn’t create your account. Check your details and try again." :
             "Couldn’t create your account. Check your connection and try again.")
        #expect(account.message == expected)
        await account.register(displayName: "Our Neighbor", email: "neighbor@example.com",
                               password: "sample-password", confirmation: "sample-password", legalAcceptance: true)
        #expect(account.user?.displayName == "Our Neighbor")
        #expect(account.message == nil)
    }

    @Test("Registration submits the entered fields and restores the account with only its saved token")
    func registrationSubmitsFieldsAndSavesSession() async throws {
        let tokens = SessionTokenStore(service: "com.huddlz.tests.\(UUID())")
        defer { Task { try? await tokens.clear() } }
        var submitted = false
        let client = AccountClient { request in
            #expect(request.url?.scheme == "https")
            #expect(request.url?.host == "huddlz.com")
            if request.url?.path == "/api/auth/register" {
                #expect(request.httpMethod == "POST")
                #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
                let data = try #require(request.httpBody)
                let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
                #expect(Set(body.keys) == ["display_name", "email", "password", "password_confirmation", "legal_acceptance"])
                #expect(body["display_name"] as? String == "Our Neighbor")
                #expect(body["email"] as? String == "neighbor@example.com")
                #expect(body["password"] as? String == "p&ss word")
                #expect(body["password_confirmation"] as? String == "p&ss word")
                #expect(body["legal_acceptance"] as? Bool == true)
                submitted = true
                return HTTPFixture.response(request, body: Self.session, status: 201)
            }
            #expect(request.url?.path == "/api/auth/me")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
            #expect(request.httpBody == nil)
            return HTTPFixture.response(request, body: "{\"user\":\(Self.user)}")
        }
        let account = AccountStore(client: client, tokens: tokens)
        await account.register(displayName: " Our Neighbor ", email: " neighbor@example.com ",
                               password: "p&ss word", confirmation: "p&ss word", legalAcceptance: true)
        #expect(submitted)
        #expect(account.user?.displayName == "Our Neighbor")
        #expect(try await tokens.load() == "fixture-token")
        let reopened = AccountStore(client: client, tokens: tokens)
        await reopened.restore()
        #expect(reopened.user?.email == "neighbor@example.com")
    }
}
