import SwiftUI

struct GroupDetailView: View {
    let id: String
    @State private var store: GroupDetailStore
    @State private var reload = UUID()
    @State private var moreRequest: UUID?
    @State private var titleBottom = CGFloat.infinity
    @State private var scrolled: CGFloat = 0

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
                                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("page")).maxY } action: { titleBottom = $0 }
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
            .coordinateSpace(.named("page"))
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in scrolled = offset }
        .background { AmbientBackground() }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            // As on the huddl page, the bar names the group only once the page's own title scrolls under it.
            ToolbarItem(placement: .principal) {
                if let group, titleBottom < scrolled {
                    Text(group.attributes.name)
                        .font(.headline)
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: titleBottom < scrolled)
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
