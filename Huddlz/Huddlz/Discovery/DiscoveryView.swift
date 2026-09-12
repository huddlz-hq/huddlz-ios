import SwiftUI

struct DiscoveryView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isShowingAccount = false
    @State private var store = DiscoveryStore()
    @State private var badges = SearchBadgeStore()
    @State private var badgeRefresh = UUID()
    @State private var searchText = ""
    @State private var preferences = DiscoveryPreferences()
    @Environment(AccountStore.self) private var account
    @State private var isChoosingLocation = false
    @State private var visibleHuddlIDs: Set<Huddl.ID> = []

    var body: some View {
        NavigationStack {
            discoveryContent
        }
        .onChange(of: searchText) { _, value in
            if value.isEmpty { preferences.query.text = "" }
        }
        .task(id: account.user?.id) { await preferences.loadProfile(for: account) }
        .sheet(isPresented: $isShowingAccount) { AccountView { preferences.selectPlace($0) } }
        .sheet(isPresented: $isChoosingLocation) {
            LocationSearchView(place: Binding(get: { preferences.query.place }, set: { preferences.selectPlace($0) }))
        }
    }

    private var discoveryContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                HStack {
                    wordmark
                    Spacer(minLength: 8)
                    Button { isShowingAccount = true } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.title3)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Account")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Find your people.")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("Find a huddl worth showing up to.")
                        .foregroundStyle(.secondary)
                }
                locationFilter
                filters
                results
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background { AmbientBackground() }
        .background { SearchBadgeLoader(store: badges, huddlIDs: visibleHuddlIDs, refresh: badgeRefresh) }
        .toolbar(horizontalSizeClass == .compact ? .hidden : .automatic, for: .navigationBar)
        .task(id: preferences.query) { await store.load(preferences.query) }
        // The search-role tab shows this field in the tab bar and expands it when tapped.
        .searchable(text: $searchText, prompt: "Search huddlz")
        .searchToolbarBehavior(.minimize)
        .onSubmit(of: .search) { preferences.query.text = searchText }
        .refreshable { await refresh() }
        .navigationDestination(for: Huddl.ID.self) { HuddlDetailView(id: $0) }
    }

    private func refresh() async {
        await store.refresh(preferences.query)
        badgeRefresh = UUID()
    }

    private var wordmark: some View {
        HStack(spacing: 10) {
            Text("h")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(uiColor: .systemBackground))
                .frame(width: 28, height: 28)
                .background(HuddlStyle.accent, in: .rect(cornerRadius: 8))
                .accessibilityHidden(true)
            Text("huddlz")
                .font(.system(size: 16, weight: .heavy))
                .tracking(-0.5)
        }
    }

    // Filters are glass chips; a chosen location keeps the accent so the active filter stands out.
    private var locationFilter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { isChoosingLocation = true } label: {
                Label(preferences.query.place?.name ?? "Anywhere", systemImage: "mappin.and.ellipse")
                    .multilineTextAlignment(.leading)
                    .frame(minHeight: 32)
            }
            .foregroundStyle(preferences.query.place == nil ? Color.primary : HuddlStyle.accent)
            .accessibilityLabel("Location: \(preferences.query.place?.name ?? "Anywhere")")
            if preferences.query.place != nil {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Menu {
                            Picker("Distance", selection: $preferences.query.distanceMiles) {
                                ForEach([5, 10, 25, 50, 100], id: \.self) { miles in
                                    Text("\(miles) miles").tag(miles)
                                }
                            }
                        } label: {
                            Text("Within \(preferences.query.distanceMiles) miles").frame(minHeight: 32)
                        }
                        .accessibilityLabel("Distance: \(preferences.query.distanceMiles) miles")
                        Button("Clear location") { preferences.selectPlace(nil) }
                            .frame(minHeight: 32)
                    }
                }
            }
        }
        .buttonStyle(.glass)
    }

    private var filters: some View {
        GlassEffectContainer(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { dateFilter; typeFilter }
                VStack(alignment: .leading, spacing: 8) { dateFilter; typeFilter }
            }
        }
        .buttonStyle(.glass)
    }

    private var dateFilter: some View {
        Menu {
            Picker("When", selection: $preferences.query.dates) {
                ForEach(DiscoveryDates.allCases) { date in Text(date.title).tag(date) }
            }
        } label: {
            Label(preferences.query.dates.title, systemImage: "calendar")
                .frame(minHeight: 32)
        }
        .foregroundStyle(preferences.query.dates == .upcoming ? Color.primary : HuddlStyle.accent)
        .accessibilityLabel("When: \(preferences.query.dates.title)")
    }

    private var typeFilter: some View {
        Menu {
            Picker("Event type", selection: $preferences.query.eventType) {
                Text("All types").tag(nil as EventType?)
                ForEach(EventType.allCases) { type in Text(type.title).tag(Optional(type)) }
            }
        } label: {
            Label(preferences.query.eventType?.title ?? "All types", systemImage: "person.2")
                .frame(minHeight: 32)
        }
        .foregroundStyle(preferences.query.eventType == nil ? Color.primary : HuddlStyle.accent)
        .accessibilityLabel("Event type: \(preferences.query.eventType?.title ?? "All types")")
    }

    @ViewBuilder private var results: some View {
        if let message = store.refreshError {
            VStack(spacing: 8) {
                if store.isRefreshing {
                    ProgressView("Refreshing huddlz…")
                } else {
                    Text("Couldn’t refresh huddlz.").font(.headline)
                    Text(message).foregroundStyle(.secondary)
                    Button("Try refreshing again") {
                        Task { await refresh() }
                    }
                    .buttonStyle(.glass)
                }
            }
            .frame(maxWidth: .infinity)
        }
        if store.isLoading {
            ProgressView("Finding huddlz…")
                .frame(maxWidth: .infinity, minHeight: 180)
                .accessibilityIdentifier("discovery-loading")
        } else if let message = store.errorMessage {
            ContentUnavailableView {
                Label("Couldn’t load huddlz", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await store.search(preferences.query) } }
                    .buttonStyle(.glassProminent)
            }
        } else if store.huddlz.isEmpty {
            ContentUnavailableView {
                Label("No huddlz found", systemImage: "magnifyingglass")
            } description: {
                Text(preferences.query.place == nil
                     ? "Try another search, a different event type, or a wider date range."
                     : "Try a wider distance, another place, or different search filters.")
            } actions: {
                if preferences.query != DiscoveryQuery() {
                    Button("Clear search and filters") { searchText = ""; preferences.selectPlace(nil); preferences.query = DiscoveryQuery() }
                        .buttonStyle(.glass)
                }
            }
        } else {
            Group {
                ForEach(store.huddlz) { huddl in
                    NavigationLink(value: huddl.id) { SearchBadgeCard(huddl: huddl, store: badges) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("huddl-\(huddl.id)")
                        .onScrollVisibilityChange(threshold: 0.1) { visible in
                            if visible {
                                visibleHuddlIDs.insert(huddl.id)
                            } else {
                                visibleHuddlIDs.remove(huddl.id)
                            }
                        }
                }
                if let message = store.moreError {
                    Text(message).foregroundStyle(.secondary)
                }
                DiscoveryPaginationFooter(store: store, visibleHuddlIDs: visibleHuddlIDs)
            }
        }
    }
}

// Keep pagination observation separate from the view that owns native refresh.
private struct DiscoveryPaginationFooter: View {
    let store: DiscoveryStore
    let visibleHuddlIDs: Set<Huddl.ID>

    private var automaticNextPage: URL? {
        guard !store.isRefreshing,
              store.moreError == nil,
              let lastID = store.huddlz.last?.id,
              visibleHuddlIDs.contains(lastID) else { return nil }
        return store.nextPage
    }

    var body: some View {
        Group {
            if store.nextPage != nil {
                Group {
                    if store.isLoadingMore {
                        ProgressView("Loading more…")
                            .accessibilityIdentifier("pagination-loading")
                    } else if store.moreError != nil {
                        Button("Try loading more again") {
                            Task { await store.loadMore() }
                        }
                        .buttonStyle(.glass)
                        .disabled(store.isRefreshing)
                    } else {
                        Color.clear.accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 48)
            }
        }
        .onChange(of: automaticNextPage, initial: true) { _, next in
            guard let next else { return }
            Task {
                guard automaticNextPage == next else { return }
                await store.loadMore()
            }
        }
    }
}
