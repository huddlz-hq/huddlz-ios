import MapKit
import SwiftUI

struct HuddlLocationView: View {
    @Environment(\.openURL) private var openURL
    @State private var location: HuddlLocationStore

    init(address: String) {
        _location = State(initialValue: HuddlLocationStore(address: address))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let item = location.item {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: item.location.coordinate,
                    latitudinalMeters: 1_000, longitudinalMeters: 1_000
                )), interactionModes: [.zoom]) {
                    Marker(item.name ?? location.address, coordinate: item.location.coordinate)
                        .tint(HuddlStyle.accent)
                }
                .frame(height: 180)
            }
            Button {
                location.open(place: { $0.openInMaps(launchOptions: nil) }, search: { openURL($0) })
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        if let name = location.item?.name, name != location.address {
                            Text(name).font(.headline).foregroundStyle(.primary)
                        }
                        Text(location.address).multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.up.forward.square")
                }
                .padding(16)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(HuddlStyle.accent)
            .accessibilityIdentifier("Open location in Maps")
            .accessibilityHint("Opens this location in Apple Maps")
        }
        .surfaceCard()
        .task { await location.resolve() }
    }
}
