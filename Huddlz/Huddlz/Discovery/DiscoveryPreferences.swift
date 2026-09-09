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
        query.place = nil
        guard let defaults = try? await account.searchDefaults(), !hasSelectedPlace else { return }
        query.place = defaults.homeLocation?.place
        query.distanceMiles = defaults.distanceMiles
    }
}
