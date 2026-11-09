import SwiftUI

struct DeleteAccountView: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var password = ""
    @State private var errorMessage: String?
    @FocusState private var isPasswordFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SheetHeader(title: "Delete your account?", subtitle: "This can’t be undone.") {
                    EmptyView()
                }
                Text(Self.consequences)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                FormField("Password") {
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($isPasswordFocused)
                        .submitLabel(.done)
                        .onSubmit { delete() }
                        .formFieldWell()
                        .disabled(account.isBusy)
                }
                Button(role: .destructive, action: delete) {
                    Text("Delete account")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.glassProminent)
                .tint(.red)
                .disabled(!canDelete)
                if account.isBusy { ProgressView("Deleting…") }
                if let errorMessage { Text(errorMessage).foregroundStyle(.secondary) }
                Button { dismiss() } label: {
                    Text("Keep my account").sheetLink()
                }
                .disabled(account.isBusy)
            }
            .padding(24)
            .padding(.top, 12)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        // Opaque: this sheet stacks on the account sheet, whose controls must not show (or read) through it.
        .background(HuddlStyle.background)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(560), .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(account.isBusy)
    }

    static let consequences = "Your name, email, photo, and API keys are removed, and you leave your groups and give up your upcoming RSVPs. Groups you own are archived and their upcoming huddlz cancelled. Past huddlz show you as “Deleted member.” Enter your password to confirm."

    private var canDelete: Bool { !password.isEmpty && !account.isBusy }

    private func delete() {
        guard canDelete else { return }
        isPasswordFocused = false
        errorMessage = nil
        Task {
            errorMessage = await account.deleteAccount(password: password)
            password = ""
            if account.user == nil { dismiss() }
        }
    }
}
