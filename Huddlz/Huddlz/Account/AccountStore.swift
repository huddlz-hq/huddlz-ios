import Foundation

import Observation

@MainActor
@Observable
final class AccountStore {
    private(set) var user: AccountUser? {
        didSet { if oldValue?.id != user?.id { sessionRevision = UUID() } }
    }
    private var sessionRevision = UUID()
    private(set) var isBusy = false
    private(set) var message: String?
    private(set) var canRetrySession = false
    private(set) var attendanceRevision = UUID()
    private let tokens: SessionTokenStore
    private let client: AccountClient
    #if DEBUG
    private var initialUITestToken: String?
    #endif

    init(client: AccountClient? = nil, tokens: SessionTokenStore? = nil) {
        self.client = client ?? AccountClient()
        if let tokens {
            self.tokens = tokens
        } else {
            var service = "com.huddlz.Huddlz.session"
            #if DEBUG
            if ProcessInfo.processInfo.environment["HUDDLZ_UI_HTTP_SCRIPT"] != nil
                || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                let id = ProcessInfo.processInfo.environment["HUDDLZ_UI_SESSION_ID"] ?? UUID().uuidString
                service += ".tests." + id
            }
            #endif
            self.tokens = SessionTokenStore(service: service)
            #if DEBUG
            let environment = ProcessInfo.processInfo.environment
            if environment["HUDDLZ_UI_HTTP_SCRIPT"] != nil, environment["HUDDLZ_UI_SESSION_ID"] != nil {
                initialUITestToken = environment["HUDDLZ_UI_INITIAL_TOKEN"]
            }
            #endif
        }
    }

    func restore() async {
        guard !isBusy else { return }
        isBusy = true
        canRetrySession = false
        message = nil
        defer { isBusy = false }
        do {
            #if DEBUG
            // Seed only the isolated UI-test Keychain, then use normal session restoration.
            if let token = initialUITestToken {
                initialUITestToken = nil
                try await tokens.save(token)
            }
            #endif
            guard let token = try await tokens.load() else { user = nil; return }
            user = try await client.currentUser(token: token)
        } catch AccountError.unauthorized {
            user = nil
            do {
                try await tokens.clear()
                message = "Your session has expired. Please sign in again."
            } catch {
                canRetrySession = true
                message = "Couldn’t clear your saved session. Please try again."
            }
        } catch is CancellationError {
            canRetrySession = true
        } catch {
            canRetrySession = true
            message = "Couldn’t check your account. Check your connection and try again."
        }
    }

    func searchDefaults() async throws -> ProfileSearchDefaults? {
        guard let userID = user?.id, let token = try await tokens.load() else { return nil }
        let defaults = try await client.searchDefaults(token: token, userID: userID)
        guard user?.id == userID else { throw CancellationError() }
        try Task.checkCancellation()
        return defaults
    }

    func attendance(huddlID: String) async throws -> AttendanceState {
        guard let userID = user?.id, let token = try await tokens.load() else { throw AccountError.unauthorized }
        let attendance = try await client.attendance(huddlID: huddlID, token: token)
        guard user?.id == userID else { throw CancellationError() }
        try Task.checkCancellation()
        return attendance
    }

    func changeAttendance(huddlID: String, action: RSVPAction) async throws -> AttendanceState {
        let session = sessionRevision
        guard let userID = user?.id, let token = try await tokens.load() else { throw AccountError.unauthorized }
        guard session == sessionRevision else { throw CancellationError() }
        do {
            let attendance = try await client.changeAttendance(huddlID: huddlID, action: action, token: token)
            guard user?.id == userID, session == sessionRevision else { throw CancellationError() }
            try Task.checkCancellation()
            attendanceRevision = UUID()
            return attendance
        } catch AccountError.unauthorized {
            guard user?.id == userID, session == sessionRevision else { throw CancellationError() }
            isBusy = true
            defer { isBusy = false }
            user = nil
            try? await tokens.clear()
            throw RSVPError(message: "Your session expired. Please sign in again.")
        } catch {
            guard user?.id == userID, session == sessionRevision else { throw CancellationError() }
            throw error
        }
    }

    func joiningLink(huddlID: String) async throws -> URL? {
        guard let userID = user?.id, let token = try await tokens.load() else { throw AccountError.unauthorized }
        let link = try await client.joiningLink(huddlID: huddlID, token: token)
        guard user?.id == userID else { throw CancellationError() }
        try Task.checkCancellation()
        return link
    }

    func attendances(huddlIDs: Set<String>) async throws -> [String: AttendanceState] {
        guard let userID = user?.id, let token = try await tokens.load() else { throw AccountError.unauthorized }
        let states = try await client.attendances(huddlIDs: huddlIDs, token: token)
        guard user?.id == userID else { throw CancellationError() }
        try Task.checkCancellation()
        return states
    }

    func agenda() async throws -> [AgendaEntry] {
        try await forCurrentUser { token in try await client.agenda(token: token) }
    }

    func groups() async throws -> GroupsPage {
        try await forCurrentUser { token in try await client.groups(token: token) }
    }

    func groupsPage(at url: URL) async throws -> GroupsPage {
        try await forCurrentUser { token in try await client.groupsPage(at: url, token: token) }
    }

    /// Runs an authenticated request and discards its result if the account changed meanwhile.
    private func forCurrentUser<Value>(_ request: (String) async throws -> Value) async throws -> Value {
        guard let userID = user?.id, let token = try await tokens.load() else { throw AccountError.unauthorized }
        let value = try await request(token)
        guard user?.id == userID else { throw CancellationError() }
        try Task.checkCancellation()
        return value
    }

    func saveHomeLocation(_ place: DiscoveryPlace) async throws {
        guard !isBusy, let user else { throw AccountError.unavailable }
        isBusy = true
        defer { isBusy = false }
        guard let token = try await tokens.load() else { throw AccountError.unauthorized }
        try await client.saveHomeLocation(userID: user.id, token: token, place: place)
    }

    func signOut() async {
        guard !isBusy else { return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            let token = try await tokens.load()
            try await tokens.clear()
            user = nil
            canRetrySession = false
            if let token {
                do {
                    try await client.signOut(token: token)
                } catch AccountError.unauthorized {
                    // The server already considers this session invalid.
                } catch {
                    message = "Signed out on this device. Couldn’t end the session on the server."
                }
            }
        } catch {
            message = "Couldn’t remove your saved session. Please try signing out again."
        }
    }

    func clearMessage() {
        guard !isBusy else { return }
        message = nil
    }

    func register(displayName: String, email: String, password: String, confirmation: String, legalAcceptance: Bool) async {
        guard !isBusy, legalAcceptance else { return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            let session = try await client.register(displayName: displayName, email: email, password: password,
                                                    confirmation: confirmation, legalAcceptance: legalAcceptance)
            try await tokens.save(session.token)
            canRetrySession = false
            user = session.user
            sessionRevision = UUID()
        } catch AccountError.invalidRegistration(let feedback) {
            message = feedback
        } catch AccountError.rateLimited {
            message = "Too many attempts. Please try again later."
        } catch TokenStoreError.unavailable {
            message = "Your account was created, but we couldn’t save your sign-in. Please return to sign in."
        } catch {
            message = "Couldn’t create your account. Check your connection and try again."
        }
    }

    func signIn(email: String, password: String) async {
        guard !isBusy else { return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            let session = try await client.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            try await tokens.save(session.token)
            canRetrySession = false
            user = session.user
            sessionRevision = UUID()
        } catch TokenStoreError.unavailable {
            message = "Couldn’t save your session securely. Please try again."
        } catch AccountError.unauthorized {
            message = "The email or password is incorrect. Try again."
        } catch AccountError.rateLimited {
            message = "Too many sign-in attempts. Please try again later."
        } catch {
            message = "Couldn’t sign in. Check your connection and try again."
        }
    }
}
