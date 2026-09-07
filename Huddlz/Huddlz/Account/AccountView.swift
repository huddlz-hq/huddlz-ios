import SwiftUI

struct AccountView: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                if let user = account.user {
                    Section {
                        if let name = user.displayName { Text(name).font(.headline) }
                        Text(user.email)
                        Button("Sign out", role: .destructive) { Task { await account.signOut() } }
                            .disabled(account.isBusy)
                    }
                } else {
                    Section("Sign in to Huddlz") {
                        TextField("Email", text: $email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .submitLabel(.go)
                            .onSubmit { signIn() }
                        Button("Sign in") { signIn() }
                            .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty || account.isBusy)
                    }
                    .disabled(account.isBusy)
                }
                if account.isBusy { ProgressView("Please wait…") }
                if account.canRetrySession {
                    Button("Try checking account again") { Task { await account.restore() } }
                        .disabled(account.isBusy)
                }
                if let message = account.message { Text(message).foregroundStyle(.secondary) }
            }
            .navigationTitle("Account")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.disabled(account.isBusy)
                }
            }
        }
        .interactiveDismissDisabled(account.isBusy)
    }

    private func signIn() {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty, !account.isBusy else { return }
        Task {
            await account.signIn(email: email, password: password)
            password = ""
            if account.user != nil { dismiss() }
        }
    }
}
