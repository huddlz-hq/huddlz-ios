import SwiftUI

struct RegistrationForm: View {
    @Environment(AccountStore.self) private var account
    @Binding var email: String
    let onSuccess: () -> Void
    let onSignIn: () -> Void
    @State private var displayName = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var legalAcceptance = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case name, email, password, confirmation }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                FormField("Display name") {
                    TextField("Display name", text: $displayName)
                        .textContentType(.nickname)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .email }
                        .formFieldWell()
                }
                FormField("Email") {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                        .formFieldWell()
                }
                FormField("Password") {
                    SecureField("Password", text: $password)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .confirmation }
                        .formFieldWell()
                }
                FormField("Confirm password") {
                    SecureField("Confirm password", text: $confirmation)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .confirmation)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                        .formFieldWell()
                }
            }
            Toggle(isOn: $legalAcceptance) {
                Text("I agree to the Terms of Service and Code of Conduct and acknowledge the Privacy Policy.")
                    .font(.footnote)
            }
            .tint(HuddlStyle.accent)
            .accessibilityIdentifier("Accept legal documents")
            HStack(spacing: 12) {
                legalLink("Terms of Service", path: "terms")
                legalLink("Code of Conduct", path: "code-of-conduct")
                legalLink("Privacy Policy", path: "privacy")
            }
            if let message = account.message {
                Text(message).foregroundStyle(.secondary)
            }
            Button(action: register) {
                HStack {
                    if account.isBusy { ProgressView() }
                    Text(account.isBusy ? "Creating account…" : "Create account")
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.glassProminent)
            .disabled(!canRegister)
            Button(action: onSignIn) {
                Text("Back to sign in").sheetLink()
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .disabled(account.isBusy)
    }

    private func legalLink(_ title: String, path: String) -> some View {
        Link(destination: URL(string: "https://huddlz.com/" + path)!) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(.rect)
        }
    }

    private var canRegister: Bool {
        !account.isBusy && legalAcceptance && !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty && !confirmation.isEmpty
    }

    private func register() {
        guard canRegister else { return }
        focusedField = nil
        Task {
            await account.register(displayName: displayName, email: email, password: password,
                                   confirmation: confirmation, legalAcceptance: legalAcceptance)
            if account.user != nil {
                password = ""
                confirmation = ""
                onSuccess()
            }
        }
    }
}
