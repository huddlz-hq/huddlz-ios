import SwiftUI

struct DiscoveryView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var store = DiscoveryStore()
    @State private var searchText = ""
    @State private var query = DiscoveryQuery()
    @State private var reload = UUID()
    @State private var isChoosingLocation = false

    var body: some View {
        NavigationStack {
            discoveryContent
        }
        .searchable(text: $searchText, prompt: "Search huddlz")
        .onSubmit(of: .search) { query.text = searchText }
        .onChange(of: searchText) { _, value in
            if value.isEmpty { query.text = "" }
        }
        .sheet(isPresented: $isChoosingLocation) {
            LocationSearchView(place: $query.place)
        }
    }

    private var discoveryContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
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
        .background(HuddlStyle.background)
        .toolbar(horizontalSizeClass == .compact ? .hidden : .automatic, for: .navigationBar)
        .task(id: query) { await store.search(query) }
        .task(id: reload) {
            // The initial request is owned by the query task.
            if didRequestRetry { await store.search(query) }
        }
        .refreshable { await store.refresh(query) }
        .navigationDestination(for: Huddl.ID.self) { HuddlDetailView(id: $0) }
    }

    @State private var didRequestRetry = false

    private var locationFilter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { isChoosingLocation = true } label: {
                Label(query.place?.name ?? "Anywhere", systemImage: "mappin.and.ellipse")
                    .multilineTextAlignment(.leading)
                    .frame(minHeight: 32)
            }
            .accessibilityLabel("Location: \(query.place?.name ?? "Anywhere")")
            if query.place != nil {
                HStack {
                    Menu {
                        Picker("Distance", selection: $query.distanceMiles) {
                            ForEach([5, 10, 25, 50, 100], id: \.self) { miles in
                                Text("\(miles) miles").tag(miles)
                            }
                        }
                    } label: {
                        Text("Within \(query.distanceMiles) miles").frame(minHeight: 32)
                    }
                    .accessibilityLabel("Distance: \(query.distanceMiles) miles")
                    Button("Clear location") { query.place = nil }
                        .frame(minHeight: 32)
                }
            }
        }
        .buttonStyle(.bordered)
    }

    private var filters: some View {
        ViewThatFits(in: .horizontal) {
            HStack { dateFilter; typeFilter }
            VStack(alignment: .leading) { dateFilter; typeFilter }
        }
        .buttonStyle(.bordered)
    }

    private var dateFilter: some View {
        Menu {
            Picker("When", selection: $query.dates) {
                ForEach(DiscoveryDates.allCases) { date in Text(date.title).tag(date) }
            }
        } label: {
            Label(query.dates.title, systemImage: "calendar")
                .frame(minHeight: 32)
        }
        .accessibilityLabel("When: \(query.dates.title)")
    }

    private var typeFilter: some View {
        Menu {
            Picker("Event type", selection: $query.eventType) {
                Text("All types").tag(nil as EventType?)
                ForEach(EventType.allCases) { type in Text(type.title).tag(Optional(type)) }
            }
        } label: {
            Label(query.eventType?.title ?? "All types", systemImage: "person.2")
                .frame(minHeight: 32)
        }
        .accessibilityLabel("Event type: \(query.eventType?.title ?? "All types")")
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
                        Task { await store.refresh(query) }
                    }
                    .buttonStyle(.bordered)
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
                Button("Try again") { didRequestRetry = true; reload = UUID() }
                    .buttonStyle(.borderedProminent)
            }
        } else if store.huddlz.isEmpty {
            ContentUnavailableView {
                Label("No huddlz found", systemImage: "magnifyingglass")
            } description: {
                Text(query.place == nil
                     ? "Try another search, a different event type, or a wider date range."
                     : "Try a wider distance, another place, or different search filters.")
            } actions: {
                if query != DiscoveryQuery() {
                    Button("Clear search and filters") { searchText = ""; query = DiscoveryQuery() }
                }
            }
        } else {
            LazyVStack(spacing: 20) {
                ForEach(store.huddlz) { huddl in
                    NavigationLink(value: huddl.id) { HuddlCard(huddl: huddl) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("huddl-\(huddl.id)")
                }
                if let message = store.moreError {
                    Text(message).foregroundStyle(.secondary)
                }
                if store.nextPage != nil {
                    Button {
                        Task { await store.loadMore() }
                    } label: {
                        if store.isLoadingMore { ProgressView("Loading more…") }
                        else { Text(store.moreError == nil ? "Load more huddlz" : "Try loading more again") }
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.isLoadingMore || store.isRefreshing)
                }
            }
        }
    }
}
