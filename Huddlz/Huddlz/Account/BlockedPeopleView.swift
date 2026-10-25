import SwiftUI

/// The people this person has blocked, each with a way to unblock them.
struct BlockedPeopleView: View {
    @Environment(AccountStore.self) private var account
    @State private var people: [BlockedPerson] = []
    @State private var loadedUserID: String?
    @State private var loadFailed = false
    @State private var unblocking: BlockedPerson.ID?
    @State private var errorMessage: String?
    @State private var retry = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Blocked organizers")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if loadFailed {
                Text("Couldn’t load the organizers you blocked.").foregroundStyle(.secondary)
                Button("Try loading blocked organizers again") { retry = UUID() }.buttonStyle(.glass)
            } else if loadedUserID == nil {
                ProgressView("Loading blocked organizers…")
            } else if people.isEmpty {
                Text("You haven’t blocked anyone. Block an organizer from the More menu on one of their huddlz.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(people) { person in
                        if person.id != people.first?.id { Divider().padding(.leading, 16) }
                        row(person)
                    }
                }
                .surfaceCard()
            }
            if let errorMessage { Text(errorMessage).font(.subheadline).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: Request(userID: account.user?.id, retry: retry)) { await load() }
    }

    private func row(_ person: BlockedPerson) -> some View {
        HStack(spacing: 12) {
            Text(person.name).font(.body)
            Spacer(minLength: 8)
            if unblocking == person.id {
                ProgressView().controlSize(.small)
            } else {
                Button("Unblock") { unblock(person) }
                    .buttonStyle(.glass)
                    .disabled(unblocking != nil)
                    .accessibilityLabel("Unblock \(person.name)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }

    private func load() async {
        loadFailed = false
        guard let userID = account.user?.id else { return }
        do {
            let result = try await account.blockedPeople()
            guard !Task.isCancelled else { return }
            people = result
            loadedUserID = userID
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            loadFailed = true
        }
    }

    private func unblock(_ person: BlockedPerson) {
        guard unblocking == nil else { return }
        unblocking = person.id
        errorMessage = nil
        Task {
            defer { unblocking = nil }
            do {
                try await account.unblock(person)
                people.removeAll { $0.id == person.id }
            } catch is CancellationError {
                return
            } catch let error as ModerationError {
                errorMessage = error.message
            } catch {
                errorMessage = "Couldn’t unblock \(person.name). Please try again."
            }
        }
    }

    private struct Request: Equatable {
        let userID: String?
        let retry: UUID
    }
}
