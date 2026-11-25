import SwiftUI

struct GroupDetailView: View {
    let id: String
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AccountStore.self) private var account
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
            if let group {
                VStack(alignment: .leading, spacing: 0) {
                    if let imageURL = group.imageURL {
                        cover(imageURL)
                    }
                    LazyVStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 14) {
                            if group.imageURL == nil {
                                GroupTile(name: group.attributes.name, size: 64)
                            }
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
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .padding(.top, group.imageURL == nil ? 20 : -24)
                }
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
                .coordinateSpace(.named("page"))
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Couldn’t load this group", systemImage: "person.2.slash")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try again") { reload = UUID() }.buttonStyle(.glassProminent)
                }
                .padding(20)
            } else {
                ProgressView("Loading group…").frame(maxWidth: .infinity, minHeight: 180)
                    .padding(20)
            }
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
        .moderation(of: .group(id), isShown: group != nil)
        .task(id: reload) { await load() }
        // A block or unblock, or signing in or out, changes which huddlz this person sees here.
        .onChange(of: Viewer(userID: account.user?.id, blocks: account.blockRevision)) {
            Task { await store.reloadHuddlz(token: await account.browsingToken()) }
        }
        .task(id: moreRequest) {
            if moreRequest != nil { await loadMore() }
        }
    }

    private func cover(_ imageURL: URL) -> some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                AsyncImage(url: imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    LinearGradient(colors: [HuddlStyle.accent.opacity(0.20), HuddlStyle.accent.opacity(0.05)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .clipped()
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 110)
                }
            }
            .clipShape(.rect(cornerRadius: horizontalSizeClass == .regular ? 24 : 0))
            .padding(.top, horizontalSizeClass == .regular ? 20 : 0)
            .accessibilityHidden(true)
    }

    private var group: HostingGroup? { store.group }
    private var huddlz: [Huddl] { store.huddlz }
    private var hasLoadedHuddlz: Bool { store.hasLoadedHuddlz }
    private var huddlzError: String? { store.huddlzError }
    private var errorMessage: String? { store.errorMessage }
    private var nextPage: URL? { store.nextPage }
    private var isLoadingMore: Bool { store.isLoadingMore }
    private var moreError: Bool { store.moreError }

    private func load() async { await store.load(token: await account.browsingToken()) }
    private func loadMore() async { await store.loadMore() }

    private struct Viewer: Equatable {
        let userID: String?
        let blocks: UUID
    }
}
