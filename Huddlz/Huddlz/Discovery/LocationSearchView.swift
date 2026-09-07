import SwiftUI

struct LocationSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var place: DiscoveryPlace?
    @State private var store = PlaceSearchStore()
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
                    TextField("City or postal code", text: $text)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .onSubmit { submit() }
                    Button("Find places", action: submit)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } footer: {
                    Text("Choose a place to find huddlz nearby.")
                }
                if let place {
                    Section("Current location") {
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
            .navigationTitle("Search location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: text) { _, _ in store.clear() }
            .task(id: request) { await store.search(request.text) }
        }
    }

    private func submit() { request = SearchRequest(text: text) }
}
