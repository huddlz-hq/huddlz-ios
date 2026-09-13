import SwiftUI

struct GroupsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AccountStore.self) private var account
    @State private var store = GroupsStore()
    @State private var retry = UUID()
    @State private var isShowingAccount = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    BrandHeader { isShowingAccount = true }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your groups")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text("The people you keep showing up for.")
                            .foregroundStyle(.secondary)
                    }
                    SignedInContent(title: "Sign in to see your groups", symbol: "person.2",
                                    description: "The groups you belong to, and their next huddlz.") {
                        // One view, so the list shares the stack's spacing and the sign-in sheet attaches once.
                        VStack(alignment: .leading, spacing: 20) { list }
                    }
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background { AmbientBackground() }
            .toolbar(horizontalSizeClass == .compact ? .hidden : .automatic, for: .navigationBar)
            .navigationTitle("Groups")
            .task(id: RequestID(userID: account.user?.id, retry: retry)) {
                await store.load(account: account)
            }
        }
        .sheet(isPresented: $isShowingAccount) { AccountView() }
    }

    @ViewBuilder private var list: some View {
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
                    .buttonStyle(.glassProminent)
            }
        } else if store.loadedUserID != nil, store.groups.isEmpty {
            ContentUnavailableView("No groups yet", systemImage: "person.2",
                                   description: Text("Open a huddl and visit its group to join."))
        } else {
            // The groups share one card, as on the canvas.
            VStack(spacing: 0) {
                ForEach(Array(store.groups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 { Divider().padding(.horizontal, 16) }
                    NavigationLink { GroupDetailView(id: group.id) } label: { GroupRow(group: group) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("group-\(group.id)")
                }
            }
            .surfaceCard()
            if store.nextPage != nil {
                if store.isLoadingMore {
                    ProgressView("Loading more…").frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 8) {
                        if store.moreFailed { Text("Couldn’t load more groups.").foregroundStyle(.secondary) }
                        Button(store.moreFailed ? "Try loading more again" : "Load more groups") {
                            Task { await store.loadMore(account: account) }
                        }
                        .buttonStyle(.glass)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
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
            GroupTile(name: group.attributes.name)
            VStack(alignment: .leading, spacing: 3) {
                Text(group.attributes.name).font(.headline)
                if let location = group.attributes.location, !location.isEmpty {
                    Text(location)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

#Preview { GroupsView().environment(AccountStore()) }
