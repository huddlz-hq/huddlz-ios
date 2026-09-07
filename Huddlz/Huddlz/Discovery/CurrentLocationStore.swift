import CoreLocation
import Observation

@MainActor
@Observable
final class CurrentLocationStore: NSObject, CLLocationManagerDelegate {
    private(set) var place: DiscoveryPlace?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private let manager: CLLocationManager
    private var timeout: Task<Void, Never>?

    override init() {
        #if DEBUG
        manager = UITestLocationManager.makeIfRequested() ?? CLLocationManager()
        #else
        manager = CLLocationManager()
        #endif
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func request() {
        guard !isLoading else { return }
        place = nil
        errorMessage = nil
        isLoading = true
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            locateIfAuthorized()
        }
    }

    func cancel() {
        isLoading = false
        timeout?.cancel()
        timeout = nil
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isLoading else { return }
        locateIfAuthorized()
    }

    private func locateIfAuthorized() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            guard timeout == nil else { return }
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(20)) }
                catch { return }
                self?.locationUnavailable()
            }
            manager.requestLocation()
        case .denied, .restricted:
            errorMessage = "Location access is off. Allow access in Settings, or search for a city or postal code."
            cancel()
        case .notDetermined:
            break
        @unknown default:
            locationUnavailable()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isLoading else { return }
        guard let location = locations.last,
              location.horizontalAccuracy >= 0,
              CLLocationCoordinate2DIsValid(location.coordinate),
              abs(location.timestamp.timeIntervalSinceNow) < 60 else {
            locationUnavailable()
            return
        }
        place = DiscoveryPlace(name: "Current location", latitude: location.coordinate.latitude,
                               longitude: location.coordinate.longitude, timeZone: nil)
        cancel()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationUnavailable()
    }

    private func locationUnavailable() {
        guard isLoading else { return }
        errorMessage = "Your location couldn’t be found. Try again or search for a city or postal code."
        cancel()
    }
}
