import SwiftUI

struct GroupsView: View {
    var body: some View {
        NavigationStack {
            SignedInContent(title: "Sign in to see your groups", symbol: "person.2",
                            description: "The groups you belong to, and their next huddlz.") {
                GroupsList()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HuddlStyle.background)
            .navigationTitle("Groups")
        }
    }
}

private struct GroupsList: View {
    @Environment(AccountStore.self) private var account
    @State private var store = GroupsStore()
    @State private var retry = UUID()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if store.isLoading {
                    ProgressView("Loading your groups…")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else if store.loadFailed {
                    ContentUnavailableView {
                        Label("Couldn’t load your groups", systemImage: "person.2.slash")
                    } description: {
                        Text("Check your connection and try again.")
                    } actions: {
                        Button("Try loading groups again") { retry = UUID() }
                            .buttonStyle(.borderedProminent)
                    }
                } else if store.loadedUserID != nil, store.groups.isEmpty {
                    ContentUnavailableView("No groups yet", systemImage: "person.2",
                                           description: Text("Open a huddl and visit its group to join."))
                } else {
                    ForEach(store.groups) { group in
                        NavigationLink { GroupDetailView(id: group.id) } label: { GroupRow(group: group) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("group-\(group.id)")
                    }
                    if store.nextPage != nil {
                        if store.isLoadingMore {
                            ProgressView("Loading more…").frame(maxWidth: .infinity)
                        } else {
                            if store.moreFailed { Text("Couldn’t load more groups.").foregroundStyle(.secondary) }
                            Button(store.moreFailed ? "Try loading more again" : "Load more groups") {
                                Task { await store.loadMore(account: account) }
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .task(id: RequestID(userID: account.user?.id, retry: retry)) {
            await store.load(account: account)
        }
    }

    private struct RequestID: Equatable {
        let userID: String?
        let retry: UUID
    }
}

private struct GroupRow: View {
    let group: HostingGroup

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .foregroundStyle(HuddlStyle.accent)
                .frame(width: 40, height: 40)
                .background(HuddlStyle.accent.opacity(0.10), in: .circle)
            VStack(alignment: .leading, spacing: 4) {
                Text(group.attributes.name).font(.headline)
                if let location = group.attributes.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(HuddlStyle.surface, in: .rect(cornerRadius: 20))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

#Preview { GroupsView().environment(AccountStore()) }
