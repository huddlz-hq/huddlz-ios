import SwiftUI

struct LocationSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var place: DiscoveryPlace?
    @State private var store = PlaceSearchStore()
    @State private var currentLocation = CurrentLocationStore()
    @State private var text = ""
    @State private var request = SearchRequest()

    private struct SearchRequest: Equatable {
        var text = ""
        var id = UUID()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        currentLocation.request()
                    } label: {
                        Label("Use current location", systemImage: "location.fill")
                    }
                    .disabled(currentLocation.isLoading)
                    if currentLocation.isLoading {
                        ProgressView("Finding your location…")
                    }
                    if let message = currentLocation.errorMessage {
                        Text(message)
                    }
                }
                Section {
                    // The keyboard's Search key runs the search.
                    Label {
                        TextField("City or postal code", text: $text)
                            .submitLabel(.search)
                            .autocorrectionDisabled()
                            .onSubmit { submit() }
                    } icon: {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Search for a city or postal code, then choose a place to find huddlz nearby.")
                }
                if let place {
                    Section("Selected location") {
                        Text(place.name)
                    }
                }
                if store.isLoading {
                    ProgressView("Finding places…")
                } else if let message = store.errorMessage {
                    Section {
                        Text(message)
                        Button("Try again", action: submit)
                    }
                } else if store.didSearch && store.places.isEmpty {
                    ContentUnavailableView("No places found", systemImage: "mappin.slash",
                                           description: Text("Try a city name or postal code."))
                } else {
                    ForEach(store.places, id: \.self) { result in
                        Button {
                            place = result
                            dismiss()
                        } label: {
                            Label(result.name, systemImage: "mappin.and.ellipse")
                                .foregroundStyle(.primary)
                                .padding(.vertical, 4)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Search location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .onChange(of: text) { _, _ in store.clear() }
            .onChange(of: currentLocation.place) { _, result in
                if let result {
                    place = result
                    dismiss()
                }
            }
            .onDisappear { currentLocation.cancel() }
            .task(id: request) { await store.search(request.text) }
        }
        // Matches the account sheets.
        .presentationBackground(.regularMaterial)
    }

    private func submit() { request = SearchRequest(text: text) }
}
