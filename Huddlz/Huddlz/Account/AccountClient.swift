import Foundation

struct AccountUser: Decodable, Equatable {
    let id: String
    let email: String
    let displayName: String?
}

struct AccountSession: Decodable {
    let token: String
    let user: AccountUser
}

struct AccountClient {
    private let fetch: (URLRequest) async throws -> (Data, URLResponse)

    init(fetch: ((URLRequest) async throws -> (Data, URLResponse))? = nil) {
        if let fetch {
            self.fetch = fetch
        } else {
            #if DEBUG
            if let service = UITestHTTPService.shared {
                self.fetch = { try await service.respond(to: $0) }
                return
            }
            #endif
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.timeoutIntervalForRequest = 30
            let session = URLSession(configuration: configuration, delegate: AccountRedirectPolicy(), delegateQueue: nil)
            self.fetch = { try await session.data(for: $0) }
        }
    }

    func signIn(email: String, password: String) async throws -> AccountSession {
        struct Credentials: Encodable { let email: String; let password: String }
        var request = URLRequest(url: URL(string: "https://huddlz.com/api/auth/sign_in")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(Credentials(email: email, password: password))
        let data = try await send(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let session = try decoder.decode(AccountSession.self, from: data)
        guard !session.token.isEmpty else { throw AccountError.unavailable }
        return session
    }

    func currentUser(token: String) async throws -> AccountUser {
        struct Document: Decodable { let user: AccountUser }
        var request = URLRequest(url: URL(string: "https://huddlz.com/api/auth/me")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await send(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Document.self, from: data).user
    }

    func signOut(token: String) async throws {
        var request = URLRequest(url: URL(string: "https://huddlz.com/api/auth/sign_out")!)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await fetch(request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw AccountError.unavailable }
        switch response.statusCode {
        case 200..<300: return data
        case 401: throw AccountError.unauthorized
        case 429: throw AccountError.rateLimited
        default: throw AccountError.unavailable
        }
    }
}

enum AccountError: Error {
    case unauthorized, rateLimited, unavailable
}

// Credentials and bearer tokens must never follow redirects to another endpoint.
private final class AccountRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
