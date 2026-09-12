import SwiftUI

/// Signed-out visitors see what a tab holds and can sign in without leaving it.
struct SignInPrompt: View {
    let title: String
    let symbol: String
    let description: String
    @State private var showsAccount = false

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(description)
        } actions: {
            Button("Sign in") { showsAccount = true }
                .buttonStyle(.borderedProminent)
        }
        .sheet(isPresented: $showsAccount) { AccountView() }
    }
}

/// Wraps a signed-in tab so the sign-in prompt appears only once the saved session has been checked.
struct SignedInContent<Content: View>: View {
    let title: String
    let symbol: String
    let description: String
    @ViewBuilder let content: () -> Content
    @Environment(AccountStore.self) private var account

    var body: some View {
        if account.user != nil {
            content()
        } else if account.isBusy {
            ProgressView("Checking your account…")
        } else {
            SignInPrompt(title: title, symbol: symbol, description: description)
        }
    }
}
