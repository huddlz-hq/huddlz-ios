import SwiftUI

struct PasswordResetView: View {
    @Binding var email: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isSending = false
    @State private var didRequestReset = false
    @State private var errorMessage: String?
    @FocusState private var isEmailFocused: Bool
    private let client = AccountClient()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(didRequestReset ? "Check your email" : "Reset your password")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                if didRequestReset {
                    Text("If an account exists for this email, we’ll send a reset link.")
                    Text("Follow the link to choose a new password on huddlz.com, then return here to sign in.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Enter your account email to request a reset link.")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email").font(.subheadline)
                        TextField("Email", text: $email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($isEmailFocused)
                            .submitLabel(.send)
                            .onSubmit { send() }
                            .padding(16)
                            .background(HuddlStyle.surface, in: .rect(cornerRadius: 14))
                            .disabled(isSending)
                    }
                    Button(action: send) {
                        Text("Send reset link")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(.white)
                            .background(HuddlStyle.accent.opacity(canSend ? 1 : 0.35), in: .rect(cornerRadius: 16))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    if isSending { ProgressView("Sending…") }
                    if let errorMessage { Text(errorMessage).foregroundStyle(.secondary) }
                }
                Button { dismiss() } label: {
                    Text("Back to sign in")
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(.rect)
                }
                .disabled(isSending)
            }
            .padding(24)
            .padding(.top, 12)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(HuddlStyle.background)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(440), .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSending)
    }

    private var canSend: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending && !didRequestReset
    }

    private func send() {
        guard canSend else { return }
        isEmailFocused = false
        isSending = true
        errorMessage = nil
        Task {
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
}
