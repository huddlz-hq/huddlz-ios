import CoreLocation
import Foundation
import Testing
@testable import Huddlz

/// Replaces only Core Location: permission answers and location fixes come from the test.
nonisolated final class SimulatedLocationManager: CLLocationManager {
    var status: CLAuthorizationStatus
    var answer: CLAuthorizationStatus
    var fixes: [Result<CLLocation, CLError>]
    private(set) var permissionRequests = 0

    init(status: CLAuthorizationStatus, answer: CLAuthorizationStatus = .authorizedWhenInUse,
         fixes: [Result<CLLocation, CLError>]) {
        self.status = status
        self.answer = answer
        self.fixes = fixes
        super.init()
    }

    override var authorizationStatus: CLAuthorizationStatus { status }

    override func requestWhenInUseAuthorization() {
        permissionRequests += 1
        status = answer
        delegate?.locationManagerDidChangeAuthorization?(self)
    }

    override func requestLocation() {
        switch fixes.removeFirst() {
        case .success(let location): delegate?.locationManager?(self, didUpdateLocations: [location])
        case .failure(let error): delegate?.locationManager?(self, didFailWithError: error)
        }
    }

    override func stopUpdatingLocation() {}
}

@MainActor
struct CurrentLocationBehaviorTests {
    private static let staugustine = CLLocation(latitude: 29.9012, longitude: -81.3124)

    @Test("Current location asks for permission only when requested, then finds the device's place")
    func currentLocationAfterPermission() {
        let manager = SimulatedLocationManager(status: .notDetermined, fixes: [.success(Self.staugustine)])
        let location = CurrentLocationStore(manager: manager)
        #expect(manager.permissionRequests == 0)
        location.request()
        #expect(manager.permissionRequests == 1)
        #expect(location.place?.latitude == 29.9012)
        #expect(location.place?.longitude == -81.3124)
        #expect(location.errorMessage == nil)
        #expect(!location.isLoading)
    }

    @Test("Denied location explains how to turn it on and finds no place", arguments: [
        CLAuthorizationStatus.notDetermined, .denied, .restricted
    ])
    func deniedLocation(initial: CLAuthorizationStatus) {
        let manager = SimulatedLocationManager(status: initial, answer: .denied, fixes: [])
        let location = CurrentLocationStore(manager: manager)
        location.request()
        #expect(location.place == nil)
        #expect(location.errorMessage == "Location access is off. Allow access in Settings, or search for a city or postal code.")
        #expect(!location.isLoading)
    }

    @Test("An unavailable location can be retried")
    func unavailableLocationCanRetry() {
        let manager = SimulatedLocationManager(status: .authorizedWhenInUse,
                                               fixes: [.failure(CLError(.locationUnknown)), .success(Self.staugustine)])
        let location = CurrentLocationStore(manager: manager)
        location.request()
        #expect(location.place == nil)
        #expect(location.errorMessage == "Your location couldn’t be found. Try again or search for a city or postal code.")
        #expect(!location.isLoading)
        location.request()
        #expect(location.errorMessage == nil)
        #expect(location.place?.latitude == 29.9012)
    }

    @Test("A stale or invalid fix is treated as unavailable")
    func staleFixIsUnavailable() {
        let stale = CLLocation(coordinate: Self.staugustine.coordinate, altitude: 0, horizontalAccuracy: 10,
                               verticalAccuracy: 10, timestamp: .now.addingTimeInterval(-600))
        let invalid = CLLocation(coordinate: Self.staugustine.coordinate, altitude: 0, horizontalAccuracy: -1,
                                 verticalAccuracy: 10, timestamp: .now)
        for fix in [stale, invalid] {
            let location = CurrentLocationStore(manager: SimulatedLocationManager(status: .authorizedWhenInUse, fixes: [.success(fix)]))
            location.request()
            #expect(location.place == nil)
            #expect(location.errorMessage == "Your location couldn’t be found. Try again or search for a city or postal code.")
        }
    }
}
