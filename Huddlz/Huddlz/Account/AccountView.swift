import SwiftUI

struct AccountView: View {
    var onHomeLocationSaved: (DiscoveryPlace) -> Void = { _ in }
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var email = ""
    @State private var password = ""
    @State private var showsPassword = false
    @State private var isResettingPassword = false
    @State private var isRegistering = false
    @State private var isChoosingHome = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case email, password, visiblePassword }

    var body: some View {
        if isChoosingHome {
            SignupLocationView { place in
                if let place { onHomeLocationSaved(place) }
                dismiss()
            }
        } else {
            accountContent
        }
    }

    private var accountContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SheetHeader(title: title, subtitle: subtitle) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Close account")
                    .disabled(account.isBusy)
                }
                if let user = account.user {
                    identity(user)
                    Button(role: .destructive) { Task { await account.signOut() } } label: {
                        Text("Sign out")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.glass)
                    .disabled(account.isBusy)
                } else if isRegistering {
                    RegistrationForm(email: $email, onSuccess: { isChoosingHome = true }, onSignIn: {
                        account.clearMessage()
                        isRegistering = false
                    })
                } else {
                    signInForm
                }
                if account.isBusy && !isRegistering { ProgressView("Please wait…") }
                if account.canRetrySession {
                    Button("Try checking account again") { Task { await account.restore() } }
                        .buttonStyle(.glass)
                        .disabled(account.isBusy)
                }
                if !isRegistering, let message = account.message {
                    Text(message).foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .padding(.top, 12)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            // The reset sheet stacks on this one; its fields must not be read (or tapped) through it.
            .accessibilityHidden(isResettingPassword)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationBackground(.regularMaterial)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize || isRegistering ? [.large] : [.height(account.user == nil ? 640 : 360), .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(account.isBusy)
        .sheet(isPresented: $isResettingPassword) { PasswordResetView(email: $email) }
    }

    private var title: String {
        account.user != nil ? "Your account" : (isRegistering ? "Create your account" : "Welcome back")
    }

    private var subtitle: String {
        account.user != nil ? "You’re signed in." : (isRegistering ? "Find your people. Join a huddl." : "Sign in to huddlz")
    }

    private var signInForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                FormField("Email") {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = showsPassword ? .visiblePassword : .password }
                        .formFieldWell()
                }
                FormField("Password") {
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
                        Button {
                            showsPassword.toggle()
                            focusedField = showsPassword ? .visiblePassword : .password
                        } label: {
                            Image(systemName: showsPassword ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 52)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(showsPassword ? "Hide password" : "Show password")
                    }
                    .formFieldWell(trailingInset: 4)
                }
            }
            Button(action: signIn) {
                Text("Sign in")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.glassProminent)
            .disabled(!canSignIn)
            VStack(spacing: 0) {
                Button {
                    focusedField = nil
                    password = ""
                    showsPassword = false
                    isResettingPassword = true
                } label: {
                    Text("Forgot password?").sheetLink()
                }
                Button {
                    focusedField = nil
                    password = ""
                    showsPassword = false
                    account.clearMessage()
                    isRegistering = true
                } label: {
                    Text("Create an account").sheetLink()
                }
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
                .font(.system(.title2, design: .rounded, weight: .heavy))
                .foregroundStyle(HuddlStyle.accent)
                .frame(width: 64, height: 64)
                .background(HuddlStyle.accent.opacity(0.12), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if !name.isEmpty { Text(name).font(.title3.bold()) }
                Text(user.email).foregroundStyle(.secondary)
            }
            .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
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
