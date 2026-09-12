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

    func register(displayName: String, email: String, password: String, confirmation: String, legalAcceptance: Bool) async throws -> AccountSession {
        struct Registration: Encodable {
            let display_name: String
            let email: String
            let password: String
            let password_confirmation: String
            let legal_acceptance: Bool
        }
        var request = URLRequest(url: URL(string: "https://huddlz.com/api/auth/register")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(Registration(
            display_name: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password, password_confirmation: confirmation, legal_acceptance: legalAcceptance))
        let data = try await send(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let session = try decoder.decode(AccountSession.self, from: data)
        guard !session.token.isEmpty else { throw AccountError.unavailable }
        return session
    }

    func saveHomeLocation(userID: String, token: String, place: DiscoveryPlace) async throws {
        guard let timeZone = place.timeZone, TimeZone(identifier: timeZone) != nil else {
            throw AccountError.unavailable
        }
        struct Input: Encodable {
            let homeLocation: String
            let homeLatitude: Double
            let homeLongitude: Double
            let homeTimeZone: String
        }
        struct Variables: Encodable { let id: String; let input: Input }
        struct Mutation: Encodable { let query: String; let variables: Variables }
        struct Problem: Decodable {}
        struct Document: Decodable {
            struct Payload: Decodable {
                struct Update: Decodable {
                    struct User: Decodable { let id: String; let homeLocation: String? }
                    let result: User?
                    let errors: [Problem]
                }
                let updateHomeLocation: Update?
            }
            let data: Payload?
            let errors: [Problem]?
        }
        var request = URLRequest(url: URL(string: "https://huddlz.com/gql")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(Mutation(
            query: """
            mutation SaveHomeLocation($id: ID!, $input: UpdateHomeLocationInput!) {
              updateHomeLocation(id: $id, input: $input) {
                result { id homeLocation }
                errors { __typename }
              }
            }
            """,
            variables: Variables(id: userID, input: Input(homeLocation: place.name,
                homeLatitude: place.latitude, homeLongitude: place.longitude, homeTimeZone: timeZone))))
        let document = try JSONDecoder().decode(Document.self, from: await send(request))
        guard document.errors?.isEmpty != false,
              let update = document.data?.updateHomeLocation, update.errors.isEmpty,
              update.result?.id == userID, update.result?.homeLocation == place.name else {
            throw AccountError.unavailable
        }
    }

    func requestPasswordReset(email: String) async throws {
        struct ResetRequest: Encodable { let email: String }
        var request = URLRequest(url: URL(string: "https://huddlz.com/api/auth/password_reset")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(ResetRequest(email: email.trimmingCharacters(in: .whitespacesAndNewlines)))
        _ = try await send(request)
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

    func searchDefaults(token: String, userID: String) async throws -> ProfileSearchDefaults {
        struct Profile: Decodable {
            let id: String
            let searchDefaults: ProfileSearchDefaults
        }
        var request = URLRequest(url: URL(string: "https://huddlz.com/api/json/profile")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await send(request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let profile = try decoder.decode(Profile.self, from: data)
        guard profile.id == userID else { throw AccountError.unavailable }
        return profile.searchDefaults
    }

    func attendance(huddlID: String, token: String) async throws -> AttendanceState {
        struct Document: Decodable {
            struct Resource: Decodable {
                struct Attributes: Decodable { let attendanceState: AttendanceState }
                let id: String
                let attributes: Attributes
            }
            let data: Resource
        }
        var components = URLComponents(url: URL(string: "https://huddlz.com/api/json/huddlz")!.appending(component: huddlID), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "fields[huddl]", value: "attendance_state")]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let document = try decoder.decode(Document.self, from: await send(request))
        guard document.data.id == huddlID else { throw AccountError.unavailable }
        return document.data.attributes.attendanceState
    }

    func changeAttendance(huddlID: String, action: RSVPAction, token: String) async throws -> AttendanceState {
        struct Document: Decodable {
            struct Resource: Decodable {
                struct Attributes: Decodable { let attendanceState: AttendanceState }
                let id: String
                let attributes: Attributes
            }
            let data: Resource
        }
        var components = URLComponents(url: URL(string: "https://huddlz.com/api/json/huddlz")!
            .appending(component: huddlID).appending(component: action.rawValue), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "fields[huddl]", value: "attendance_state")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": ["type": "huddl", "id": huddlID, "attributes": [:]]])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let (data, response) = try await fetch(request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw AccountError.unavailable }
        switch response.statusCode {
        case 200..<300: break
        case 401: throw AccountError.unauthorized
        case 403, 404: throw RSVPError(message: "This huddl isn’t accepting RSVP changes.")
        case 400, 422:
            struct Errors: Decodable {
                struct Detail: Decodable { let detail: String?; let message: String? }
                let errors: [Detail]
            }
            let messages = (try? JSONDecoder().decode(Errors.self, from: data))?.errors.compactMap {
                ($0.detail ?? $0.message)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let readable = messages.flatMap { messages in
                !messages.isEmpty && messages.allSatisfy {
                    !$0.isEmpty && $0.count <= 240 && $0.rangeOfCharacter(from: .controlCharacters) == nil
                } ? messages.joined(separator: "\n") : nil
            }
            throw RSVPError(message: readable ?? "This huddl isn’t accepting RSVP changes.")
        case 429: throw RSVPError(message: "Too many attempts. Please wait a moment and try again.")
        default: throw AccountError.unavailable
        }
        let document = try decoder.decode(Document.self, from: data)
        guard document.data.id == huddlID else { throw AccountError.unavailable }
        return document.data.attributes.attendanceState
    }

    func joiningLink(huddlID: String, token: String) async throws -> URL? {
        struct Document: Decodable {
            struct Resource: Decodable {
                struct Attributes: Decodable { let visibleVirtualLink: String? }
                let id: String
                let attributes: Attributes
            }
            let data: Resource
        }
        var components = URLComponents(url: URL(string: "https://huddlz.com/api/json/huddlz")!.appending(component: huddlID), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "fields[huddl]", value: "visible_virtual_link")]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let document = try decoder.decode(Document.self, from: await send(request))
        guard document.data.id == huddlID else { throw AccountError.unavailable }
        guard let value = document.data.attributes.visibleVirtualLink,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let url = URL(string: value),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else { throw AccountError.unavailable }
        return url
    }

    func attendances(huddlIDs: Set<String>, token: String) async throws -> [String: AttendanceState] {
        struct Document: Decodable {
            struct Resource: Decodable {
                struct Attributes: Decodable { let attendanceState: AttendanceState? }
                let id: String
                let attributes: Attributes
            }
            let data: [Resource]
        }
        var states: [String: AttendanceState] = [:]
        let ids = huddlIDs.sorted()
        for start in stride(from: 0, to: ids.count, by: 20) {
            let batch = ids[start..<min(start + 20, ids.count)]
            var components = URLComponents(string: "https://huddlz.com/api/json/huddlz")!
            components.queryItems = [URLQueryItem(name: "fields[huddl]", value: "attendance_state"),
                                     URLQueryItem(name: "date_filter", value: "all"),
                                     URLQueryItem(name: "page[limit]", value: "20")]
                + batch.map { URLQueryItem(name: "filter[id][in][]", value: $0) }
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let document = try decoder.decode(Document.self, from: await send(request))
            for resource in document.data where batch.contains(resource.id) {
                states[resource.id] = resource.attributes.attendanceState
            }
        }
        return states
    }

    /// Upcoming huddlz the member is going to or waitlisted for, soonest first.
    func agenda(token: String) async throws -> [AgendaEntry] {
        var components = URLComponents(string: "https://huddlz.com/api/json/huddlz/upcoming")!
        components.queryItems = ["confirmed", "waitlisted"].map { URLQueryItem(name: "filter[attendance_state][in][]", value: $0) }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")
        let data = try await send(request)
        struct Document: Decodable { let data: [AgendaEntry] }
        return try JSONDecoder.huddlz.decode(Document.self, from: data).data.filter { $0.attendance != .none }
    }

    func groups(token: String) async throws -> GroupsPage {
        var components = URLComponents(url: Self.groupsURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "page[limit]", value: "20")]
        return try await groupsPage(at: components.url!, token: token)
    }

    /// Follows only the API's own next link for the member's groups, never another route or host.
    func groupsPage(at url: URL, token: String) async throws -> GroupsPage {
        let base = Self.groupsURL
        guard url.scheme == base.scheme, url.host == base.host, url.port == base.port,
              url.path == base.path, url.user == nil, url.password == nil else { throw AccountError.unavailable }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await send(request)
        struct Document: Decodable {
            let data: [HostingGroup]
            let links: Links?
            struct Links: Decodable { let next: URL? }
        }
        let document = try JSONDecoder().decode(Document.self, from: data)
        return GroupsPage(groups: document.data, next: document.links?.next)
    }

    private static let groupsURL = URL(string: "https://huddlz.com/api/json/groups/mine")!

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
        case 422:
            struct ValidationErrors: Decodable {
                struct Detail: Decodable { let message: String }
                let errors: [Detail]
            }
            let messages = (try? JSONDecoder().decode(ValidationErrors.self, from: data))?.errors.map { $0.message.trimmingCharacters(in: .whitespacesAndNewlines) }
            // The API currently sometimes returns multiline exception descriptions.
            // Keep those out of the UI while allowing concise validation messages.
            let readable = messages.flatMap { messages in
                !messages.isEmpty && messages.allSatisfy {
                    !$0.isEmpty && $0.count <= 240 && $0.rangeOfCharacter(from: .controlCharacters) == nil
                } ? messages.joined(separator: "\n") : nil
            }
            throw AccountError.invalidRegistration(readable ?? "Couldn’t create your account. Check your details and try again.")
        case 429: throw AccountError.rateLimited
        default: throw AccountError.unavailable
        }
    }
}

struct GroupsPage {
    let groups: [HostingGroup]
    let next: URL?
}

enum AccountError: Error {
    case unauthorized, rateLimited, unavailable
    case invalidRegistration(String)
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

enum RSVPAction: String {
    case reserve = "rsvp"
    case cancel = "cancel_rsvp"
}

struct RSVPError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
