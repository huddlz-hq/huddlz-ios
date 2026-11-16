import Foundation
import Observation

/// Requests a password reset link and remembers whether one was sent.
@MainActor
@Observable
final class PasswordResetRequest {
    private(set) var isSending = false
    private(set) var didRequestReset = false
    private(set) var errorMessage: String?
    private let client: AccountClient

    init(client: AccountClient? = nil) {
        self.client = client ?? AccountClient()
    }

    func canSend(email: String) -> Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending && !didRequestReset
    }

    func send(email: String) async {
        guard canSend(email: email) else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await client.requestPasswordReset(email: email)
            didRequestReset = true
        } catch AccountError.rateLimited {
            errorMessage = "Too many requests. Please try again later."
        } catch {
            errorMessage = "Couldn’t request a reset link. Check your connection and try again."
        }
    }
}
