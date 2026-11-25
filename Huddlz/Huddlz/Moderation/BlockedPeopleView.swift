import SwiftUI

/// The people this person has blocked, each with a way to unblock them.
struct BlockedPeopleView: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var store = BlockedPeopleStore()
    @State private var retry = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SheetHeader(title: "Blocked people", subtitle: "You don’t see huddlz they organize. They aren’t told.") {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Close blocked people")
                }
                if store.loadFailed {
                    Text("Couldn’t load the people you blocked.").foregroundStyle(.secondary)
                    Button("Try loading blocked people again") { retry = UUID() }.buttonStyle(.glass)
                } else if store.loadedUserID == nil {
                    ProgressView("Loading blocked people…").frame(maxWidth: .infinity, minHeight: 120)
                } else if store.people.isEmpty {
                    Text("You haven’t blocked anyone. To block someone, open the More menu on one of their huddlz or groups.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(store.people) { person in
                            if person.id != store.people.first?.id { Divider().padding(.horizontal, 16) }
                            row(person)
                        }
                    }
                    .surfaceCard()
                }
                if let message = store.errorMessage { Text(message).foregroundStyle(.secondary) }
            }
            .padding(24)
            .padding(.top, 12)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        // Opaque: this sheet stacks on the account sheet, whose rows must not show (or read) through it.
        .background(HuddlStyle.background)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task(id: Request(userID: account.user?.id, retry: retry)) { await store.load(account: account) }
        // The list belongs to the signed-in person; once they are signed out there is nothing to show.
        .onChange(of: account.user == nil) { _, signedOut in if signedOut { dismiss() } }
    }

    private func row(_ person: BlockedPerson) -> some View {
        HStack(spacing: 12) {
            Text(person.name)
            Spacer(minLength: 8)
            if store.unblocking == person.id {
                ProgressView().controlSize(.small)
            } else {
                Button("Unblock") { Task { await store.unblock(person, account: account) } }
                    .buttonStyle(.glass)
                    .disabled(store.unblocking != nil)
                    .accessibilityLabel("Unblock \(person.name)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }

    private struct Request: Equatable {
        let userID: String?
        let retry: UUID
    }
}
