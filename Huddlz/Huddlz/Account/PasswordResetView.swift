import SwiftUI
import Observation

struct PasswordResetView: View {
    @Binding var email: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var reset = PasswordResetRequest()
    @FocusState private var isEmailFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SheetHeader(title: reset.didRequestReset ? "Check your email" : "Reset your password",
                            subtitle: reset.didRequestReset
                                ? "If an account exists for this email, we’ll send a reset link."
                                : "Enter your account email to request a reset link.") {
                    EmptyView()
                }
                if reset.didRequestReset {
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
                            .disabled(reset.isSending)
                    }
                    Button(action: send) {
                        Text("Send reset link")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!canSend)
                    if reset.isSending { ProgressView("Sending…") }
                    if let errorMessage = reset.errorMessage { Text(errorMessage).foregroundStyle(.secondary) }
                }
                Button { dismiss() } label: {
                    Text("Back to sign in").sheetLink()
                }
                .disabled(reset.isSending)
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
        .interactiveDismissDisabled(reset.isSending)
    }

    private var canSend: Bool { reset.canSend(email: email) }

    private func send() {
        guard canSend else { return }
        isEmailFocused = false
        Task { await reset.send(email: email) }
    }
}
