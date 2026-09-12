import SwiftUI

/// Signed-out visitors see what a tab holds and can sign in without leaving it.
struct SignInPrompt: View {
    let title: String
    let symbol: String
    let description: String
    let signIn: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(description)
        } actions: {
            Button("Sign in", action: signIn)
                .buttonStyle(.glassProminent)
        }
    }
}

/// Wraps a signed-in tab so the sign-in prompt appears only once the saved session has been checked.
struct SignedInContent<Content: View>: View {
    let title: String
    let symbol: String
    let description: String
    @ViewBuilder let content: () -> Content
    @Environment(AccountStore.self) private var account
    @State private var showsAccount = false

    var body: some View {
        Group {
            if account.user != nil {
                content()
            } else if account.isBusy {
                ProgressView("Checking your account…")
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                SignInPrompt(title: title, symbol: symbol, description: description) {
                    showsAccount = true
                }
                .frame(maxWidth: .infinity, minHeight: 240)
            }
        }
        .sheet(isPresented: $showsAccount) { AccountView() }
    }
}
