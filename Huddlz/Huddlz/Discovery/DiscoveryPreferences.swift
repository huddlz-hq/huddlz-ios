import Foundation
import Observation

struct ProfileSearchDefaults: Decodable {
    let homeLocation: HomeLocation?
    let distanceMiles: Int

    struct HomeLocation: Decodable {
        let label: String?
        let latitude: Double
        let longitude: Double
        let timeZone: String

        var place: DiscoveryPlace {
            DiscoveryPlace(name: label ?? "Home area", latitude: latitude, longitude: longitude, timeZone: timeZone)
        }
    }
}

@MainActor
@Observable
final class DiscoveryPreferences {
    var query = DiscoveryQuery()

    private var hasSelectedPlace = false

    func selectPlace(_ place: DiscoveryPlace?) {
        hasSelectedPlace = true
        query.place = place
    }

    func loadProfile(for account: AccountStore) async {
        guard !hasSelectedPlace else { return }
        let defaults = try? await account.searchDefaults()
        guard !hasSelectedPlace, !Task.isCancelled else { return }
        query.place = defaults?.homeLocation?.place
        if let defaults { query.distanceMiles = defaults.distanceMiles }
    }
}
