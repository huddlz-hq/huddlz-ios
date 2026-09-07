import SwiftUI

/// Keeps bottom search independent of the scroll view's native refresh control.
struct DiscoverySearchBar: UIViewRepresentable {
    @Binding var text: String
    let onSearch: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UISearchBar {
        let bar = UISearchBar()
        bar.placeholder = "Search huddlz"
        bar.searchBarStyle = .minimal
        bar.delegate = context.coordinator
        return bar
    }

    func updateUIView(_ bar: UISearchBar, context: Context) {
        context.coordinator.parent = self
        if bar.text != text { bar.text = text }
    }

    final class Coordinator: NSObject, UISearchBarDelegate {
        var parent: DiscoverySearchBar

        init(_ parent: DiscoverySearchBar) { self.parent = parent }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            parent.text = searchText
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            parent.onSearch()
            searchBar.resignFirstResponder()
        }
    }
}
