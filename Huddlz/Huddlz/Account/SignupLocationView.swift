import SwiftUI

struct SignupLocationView: View {
    @Environment(AccountStore.self) private var account
    @State private var currentLocation = CurrentLocationStore()
    @State private var lookupTask: Task<Void, Never>?
    @State private var isDetecting = false
    @State private var lookupError: String?
    @State private var selectedCity: DiscoveryPlace?
    @State private var isChoosingCity = false
    @State private var isSaving = false
    @State private var saveFailed = false
    let onFinish: (DiscoveryPlace?) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.largeTitle)
                    .foregroundStyle(HuddlStyle.accent)
                    .accessibilityHidden(true)
                Text("Where should we find huddlz?")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Choose a home city to find huddlz nearby. You can do this later.")
                    .foregroundStyle(.secondary)
                if let selectedCity {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your home city").font(.subheadline).foregroundStyle(.secondary)
                        Text(selectedCity.name).font(.title3.bold())
                        Text("Visiting? Choose the city you call home.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surfaceCard()
                    if saveFailed {
                        Text("Couldn’t save your city. Try again, or do this later.")
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        cancelLookup()
                        isSaving = true
                        Task {
                            defer { isSaving = false }
                            do {
                                try await account.saveHomeLocation(selectedCity)
                                onFinish(selectedCity)
                            } catch {
                                saveFailed = true
                            }
                        }
                    } label: {
                        Text(saveFailed ? "Retry" : "Save home city")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.glassProminent)
                }
                Button {
                    cancelLookup()
                    isChoosingCity = true
                } label: {
                    Label("Choose a city", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.glass)
                Button {
                    lookupError = nil
                    isDetecting = true
                    currentLocation.request()
                    if let message = currentLocation.errorMessage {
                        lookupError = message
                        isDetecting = false
                    }
                } label: {
                    Label("Use current location", systemImage: "location.fill")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.glass)
                .disabled(isDetecting)
                if isDetecting { ProgressView("Finding your city…") }
                if let message = lookupError {
                    Text(message).foregroundStyle(.secondary)
                }
                if isSaving { ProgressView("Saving your city…") }
                Button { cancelLookup(); onFinish(nil) } label: {
                    Text("Not now").sheetLink()
                }
            }
            .padding(24)
            .disabled(isSaving)
        }
        .presentationBackground(.regularMaterial)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSaving)
        .onChange(of: currentLocation.errorMessage) { _, message in
            if let message {
                lookupError = message
                isDetecting = false
            }
        }
        .onChange(of: currentLocation.place) { _, place in
            guard isDetecting, let place else { return }
            lookupTask = Task {
                do {
                    let city = try await HomeCityLookup().city(near: place)
                    guard !Task.isCancelled else { return }
                    selectedCity = city
                    saveFailed = false
                } catch {
                    guard !Task.isCancelled else { return }
                    lookupError = "Your city couldn’t be found. Try again or choose a city."
                }
                isDetecting = false
            }
        }
        .onDisappear { cancelLookup() }
        .sheet(isPresented: $isChoosingCity) {
            SignupCitySearchView { city in
                selectedCity = city
                saveFailed = false
            }
        }
    }
    private func cancelLookup() {
        isDetecting = false
        currentLocation.cancel()
        lookupTask?.cancel()
        lookupTask = nil
        lookupError = nil
    }

}

private struct SignupCitySearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = PlaceSearchStore(citiesOnly: true)
    @State private var text = ""
    @State private var search = Search()
    let onSelect: (DiscoveryPlace) -> Void

    private struct Search: Equatable {
        var text = ""
        var id = UUID()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("City", text: $text)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { submit() }
                    Button("Find cities", action: submit)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if store.isLoading {
                    ProgressView("Finding cities…")
                } else if let message = store.errorMessage {
                    Text(message)
                    Button("Try again", action: submit)
                } else if store.didSearch && store.places.isEmpty {
                    ContentUnavailableView("No cities found", systemImage: "mappin.slash",
                                           description: Text("Try a city name and state or country."))
                } else {
                    ForEach(store.places, id: \.self) { city in
                        Button {
                            onSelect(city)
                            dismiss()
                        } label: {
                            Label(city.name, systemImage: "mappin.and.ellipse")
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Choose a city")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: text) { _, _ in store.clear() }
            .task(id: search) { await store.search(search.text) }
        }
    }

    private func submit() { search = Search(text: text) }
}
