import SwiftUI

struct HostingGroup: Decodable, Identifiable {
    let id: String
    let attributes: Attributes

    struct Attributes: Decodable {
        let name: String
        let description: String?
        let location: String?
    }
}

struct GroupDetailView: View {
    let id: String
    @State private var store: GroupDetailStore
    @State private var reload = UUID()
    @State private var moreRequest: UUID?

    init(id: String) {
        self.id = id
        _store = State(initialValue: GroupDetailStore(id: id))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if let group {
                    HStack(spacing: 14) {
                        GroupTile(name: group.attributes.name, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.attributes.name)
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            if let location = group.attributes.location, !location.isEmpty {
                                Label(location, systemImage: "mappin.and.ellipse")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About this group").font(.title3.bold())
                        Text(group.attributes.description ?? "The group hasn’t added a description yet.")
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Text("Upcoming huddlz").font(.title3.bold())
                    if let huddlzError {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Couldn’t load upcoming huddlz.").font(.headline)
                            Text(huddlzError).foregroundStyle(.secondary)
                            Button("Try loading huddlz again") { reload = UUID() }.buttonStyle(.glass)
                        }
                    } else if !hasLoadedHuddlz {
                        ProgressView("Loading huddlz…").frame(maxWidth: .infinity, minHeight: 120)
                    } else if huddlz.isEmpty {
                        ContentUnavailableView("No upcoming huddlz", systemImage: "calendar",
                                               description: Text("Check back for the group’s next gathering."))
                    }
                    ForEach(huddlz) { huddl in
                        NavigationLink { HuddlDetailView(id: huddl.id) } label: { HuddlCard(huddl: huddl) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("huddl-\(huddl.id)")
                    }
                    if nextPage != nil {
                        if isLoadingMore {
                            ProgressView("Loading more…").frame(maxWidth: .infinity)
                        } else {
                            if moreError { Text("Couldn’t load more huddlz.").foregroundStyle(.secondary) }
                            Button(moreError ? "Try loading more again" : "Load more huddlz") { moreRequest = UUID() }
                                .buttonStyle(.glass)
                                .frame(maxWidth: .infinity)
                        }
                    }
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("Couldn’t load this group", systemImage: "person.2.slash")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Try again") { reload = UUID() }.buttonStyle(.glassProminent)
                    }
                } else {
                    ProgressView("Loading group…").frame(maxWidth: .infinity, minHeight: 180)
                }
            }
            .padding(20)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background { AmbientBackground() }
        .navigationTitle("The group")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: reload) { await load() }
        .task(id: moreRequest) {
            if moreRequest != nil { await loadMore() }
        }
    }

    private var group: HostingGroup? { store.group }
    private var huddlz: [Huddl] { store.huddlz }
    private var hasLoadedHuddlz: Bool { store.hasLoadedHuddlz }
    private var huddlzError: String? { store.huddlzError }
    private var errorMessage: String? { store.errorMessage }
    private var nextPage: URL? { store.nextPage }
    private var isLoadingMore: Bool { store.isLoadingMore }
    private var moreError: Bool { store.moreError }

    private func load() async { await store.load() }
    private func loadMore() async { await store.loadMore() }
}
