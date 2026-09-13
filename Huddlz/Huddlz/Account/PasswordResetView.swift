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
            VStack(alignment: .leading, spacing: 22) {
                SheetHeader(title: didRequestReset ? "Check your email" : "Reset your password",
                            subtitle: didRequestReset
                                ? "If an account exists for this email, we’ll send a reset link."
                                : "Enter your account email to request a reset link.") {
                    EmptyView()
                }
                if didRequestReset {
                    Text("Follow the link to choose a new password on huddlz.com, then return here to sign in.")
                        .foregroundStyle(.secondary)
                } else {
                    FormField("Email") {
                        TextField("Email", text: $email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($isEmailFocused)
                            .submitLabel(.send)
                            .onSubmit { send() }
                            .formFieldWell()
                            .disabled(isSending)
                    }
                    Button(action: send) {
                        Text("Send reset link")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!canSend)
                    if isSending { ProgressView("Sending…") }
                    if let errorMessage { Text(errorMessage).foregroundStyle(.secondary) }
                }
                Button { dismiss() } label: {
                    Text("Back to sign in").sheetLink()
                }
                .disabled(isSending)
            }
            .padding(24)
            .padding(.top, 12)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        // Opaque: this sheet stacks on the account sheet, whose fields must not show (or read) through it.
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
