import SwiftUI

struct AccountView: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var email = ""
    @State private var password = ""
    @State private var showsPassword = false
    @State private var isResettingPassword = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case email, password, visiblePassword }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    Text(account.user == nil ? "Welcome back" : "Your account")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .background(HuddlStyle.surface, in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close account")
                    .disabled(account.isBusy)
                }
                if let user = account.user {
                    identity(user)
                    Button(role: .destructive) { Task { await account.signOut() } } label: {
                        Text("Sign out")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(HuddlStyle.surface, in: .rect(cornerRadius: 16))
                            .contentShape(.rect)
                    }
                    .disabled(account.isBusy)
                } else {
                    signInForm
                }
                if account.isBusy { ProgressView("Please wait…") }
                if account.canRetrySession {
                    Button("Try checking account again") { Task { await account.restore() } }
                        .disabled(account.isBusy)
                }
                if let message = account.message {
                    Text(message).foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .padding(.top, 12)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(HuddlStyle.background)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(account.user == nil ? 540 : 340), .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(account.isBusy)
        .sheet(isPresented: $isResettingPassword) { PasswordResetView(email: $email) }
    }

    private var signInForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Sign in to Huddlz").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text("Email").font(.subheadline)
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = showsPassword ? .visiblePassword : .password }
                    .padding(16)
                    .background(HuddlStyle.surface, in: .rect(cornerRadius: 14))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Password").font(.subheadline)
                HStack(spacing: 0) {
                    Group {
                        if showsPassword {
                            TextField("Password", text: $password)
                                .focused($focusedField, equals: .visiblePassword)
                        } else {
                            SecureField("Password", text: $password)
                                .focused($focusedField, equals: .password)
                        }
                    }
                    .textContentType(.password)
                    .submitLabel(.go)
                    .onSubmit { signIn() }
                    .padding(.leading, 16)
                    .padding(.vertical, 16)
                    Button {
                        showsPassword.toggle()
                        focusedField = showsPassword ? .visiblePassword : .password
                    } label: {
                        Image(systemName: showsPassword ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                            .frame(width: 52, height: 52)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showsPassword ? "Hide password" : "Show password")
                }
                .background(HuddlStyle.surface, in: .rect(cornerRadius: 14))
            }
            Button(action: signIn) {
                Text("Sign in")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(.white)
                    .background(HuddlStyle.accent.opacity(canSignIn ? 1 : 0.35), in: .rect(cornerRadius: 16))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!canSignIn)
            Button {
                focusedField = nil
                password = ""
                showsPassword = false
                isResettingPassword = true
            } label: {
                Text("Forgot password?")
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(.rect)
            }
            Text("Browse anytime. Sign in when you’re ready.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .disabled(account.isBusy)
    }

    private var canSignIn: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty && !account.isBusy
    }

    private func identity(_ user: AccountUser) -> some View {
        let name = user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let initials = name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first).map(String.init).joined()
        return HStack(spacing: 16) {
            Text(initials.isEmpty ? String(user.email.prefix(1)).uppercased() : initials.uppercased())
                .font(.title2.weight(.semibold))
                .frame(width: 72, height: 72)
                .background(HuddlStyle.accent.opacity(0.25), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if !name.isEmpty { Text(name).font(.title3.bold()) }
                Text(user.email).foregroundStyle(.secondary)
            }
            .textSelection(.enabled)
        }
    }

    private func signIn() {
        guard canSignIn else { return }
        focusedField = nil
        Task {
            await account.signIn(email: email, password: password)
            password = ""
            showsPassword = false
            if account.user != nil { dismiss() }
        }
    }
}
