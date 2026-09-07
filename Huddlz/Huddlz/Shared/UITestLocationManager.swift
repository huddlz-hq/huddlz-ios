#if DEBUG
import CoreLocation

/// Fails one external location request; authorization and subsequent fixes stay real.
final class UITestLocationManager: CLLocationManager {
    private var shouldFail = true

    static func makeIfRequested() -> CLLocationManager? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["HUDDLZ_UI_HTTP_SCRIPT"] != nil,
              environment["HUDDLZ_UI_LOCATION_FAIL_FIRST"] == "1" else { return nil }
        return UITestLocationManager()
    }

    override func requestLocation() {
        if shouldFail {
            shouldFail = false
            delegate?.locationManager?(self, didFailWithError: CLError(.locationUnknown))
        } else {
            super.requestLocation()
        }
    }
}
#endif
