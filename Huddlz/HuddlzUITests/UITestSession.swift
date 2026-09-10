import XCTest

extension XCUIApplication {
    /// Prepare a real saved session when signing in is a precondition, not the behavior under test.
    @MainActor
    func launchWithSavedSession() {
        precondition(launchEnvironment["HUDDLZ_UI_HTTP_SCRIPT"] != nil)
        precondition(launchEnvironment["HUDDLZ_UI_SESSION_ID"] != nil)
        launchEnvironment["HUDDLZ_UI_INITIAL_TOKEN"] = "fixture-token"
        launch()
        // Relaunch must use the Keychain state left by the app, including sign-out.
        launchEnvironment.removeValue(forKey: "HUDDLZ_UI_INITIAL_TOKEN")
    }
}
