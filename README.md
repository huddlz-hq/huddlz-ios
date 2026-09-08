# Huddlz iOS

Native iOS app built with Swift and SwiftUI. Public discovery connects to huddlz.com without signing in. No third-party dependencies.

## Requirements

- Xcode 26.6 (used to create this project)
- An iOS simulator runtime supported by your Xcode installation (the starter used iOS 26.5)
- Minimum supported OS: iOS 26.0; iPhone and iPad supported by the template. Use iOS 26 as the baseline; guard APIs introduced in later releases with availability checks.

## Run

1. Open `Huddlz/Huddlz.xcodeproj` in Xcode.
2. Select the `Huddlz` scheme and an iPhone simulator.
3. Press Command-R to build and run.
4. Press Command-U to run tests.

## Physical device setup

Add your Apple account in Xcode Settings, then select your development team under the app target's Signing & Capabilities tab. Automatic signing is enabled. Use the same team for test targets when testing on a physical device.

The initial bundle identifier is `com.huddlz.Huddlz`. Confirm the organization's identifier before registering the app for distribution.

## Layout

- `Huddlz/Huddlz/`: SwiftUI app entry point, discovery feature, shared UI, and assets.
- `Huddlz/HuddlzTests/`: Swift Testing unit test target.
- `Huddlz/HuddlzUITests/`: XCTest UI and launch tests.

Keep new code grouped by feature as features are added. Add shared UI and networking code when needed. Store private server credentials on the backend, never in the app or repository.

## Public discovery

Browse real huddlz in cards, submit text with the keyboard’s Search action, and filter by event type (all, in person, online, hybrid) and date (all upcoming, this week, this month). Clear the search field to reset the text query. Pull to refresh while keeping the current cards visible. A failed refresh keeps the cards and filters and offers retry. Bottom search uses a native UIKit search bar: in this layout on iOS 26.5, SwiftUI’s searchable integration detaches the refresh control. Keeping search separate preserves native pull-to-refresh feedback. Scroll near the last card to load the next batch. A bottom spinner shows progress; a failed batch keeps the cards and offers retry. Loading stops after the final batch. Opening a card fetches current details separately. Event times display in the event’s time zone.

In-person and hybrid details show a native map when Apple Maps resolves the venue to one result. Tap the address row to open that place in Maps and choose directions. The API currently supplies location text without coordinates; failed, empty, or ambiguous lookups keep the address available as a Maps search. Online events and unannounced locations have no map action. A separate live check on September 7, 2026 resolved both the DOS Coffee address in St. Augustine and the Jacksonville Beach venue to one place in Apple Maps.

Choose Anywhere to search for a city or postal code with Apple Maps. Select a place, then choose a distance of 5, 10, 25, 50, or 100 miles. Clear location returns to browsing anywhere and keeps the event search and filters. Place searches run when submitted. Use current location requests location access only after you choose that action, then uses a single fix to find nearby huddlz. Denied access or an unavailable location leaves manual place search available. Leaving the picker cancels a pending lookup.

The client uses anonymous, cookie-free requests to the public JSON API:

- `GET /api/json/huddlz` with `date_filter`, `query`, `event_type`, `search_time_zone`, and `page[limit]`.
- `GET /api/json/huddlz/{id}` for details.
- Pagination follows same-origin discovery links returned by the API.
- Location searches add `search_latitude`, `search_longitude`, and `distance_miles`. Relative date filters use the selected place’s time zone when available, otherwise the device’s time zone.

Schema: https://huddlz.com/api/json/open_api; browser docs: https://huddlz.com/api/json/swaggerui. Verified September 6, 2026. The deployed API rejects the documented `sort=soonest`, so the app uses default ordering. Group discovery, authentication, and RSVP remain separate work. Missing thumbnails use an event-type illustration; unavailable host/attendance data is not invented.

Design reference: `prototype/issue-1-core-journey`, variant A (cards). The prototype and simulated account/RSVP flow remain on that branch.

## Accounts

Open Account from discovery to sign in with an existing Huddlz account. Successful sign-in returns to the current search and filters. Compact account sheets use persistent field labels, a show-password control, and a prominent sign-in button. They expand for the keyboard and accessibility text sizes. The signed-in sheet groups initials, name, and email above sign-out. Registration, password reset, authenticated RSVP, and profile editing remain follow-up work under #3–#5.

Authentication uses the dedicated JSON endpoints `POST /api/auth/sign_in`, `GET /api/auth/me`, and `DELETE /api/auth/sign_out`. Requests are cookie-free and do not follow redirects. Only the bearer token is saved, using device-only Keychain storage accessible while unlocked. Passwords are cleared from the form after submission. The app checks a saved session on launch and when it returns to the foreground; expired sessions are removed, while temporary failures offer retry. Sign-out removes the local token before attempting server revocation, with clear feedback if the server cannot be reached. Public discovery remains available without an account.

## Behavior tests

Use Command-U in Xcode to run the suite. `HuddlzTests` exercises discovery through its public interface with controlled HTTP responses. `DiscoveryUITests` drives search, filters, details, empty states, and retry in Simulator. Test names describe the behavior they protect.

UI tests pass a response script through `HUDDLZ_UI_HTTP_SCRIPT`. The debug build uses it only at the HTTP boundary; requests, decoding, state, and views remain real. A missing or invalid scripted response fails locally instead of contacting production. Release builds exclude this hook.

State timing tests hold and release responses explicitly, so cancellation and overlapping searches do not depend on sleeps. Refresh tests cover retained cards, failure, cancellation, and a newer search superseding a pending refresh. A native pull gesture verifies visible cards, preserved filters, and retry after failure. A visual test delays the HTTP response and captures the native spinner during refresh; restoring the conflicting search integration makes this test fail. Keep live API smoke checks separate from this deterministic suite.

Pagination tests scroll through real cards and verify bottom progress, stable scroll position, explicit retry, and continued loading through a repeated batch. State tests cover overlapping requests, the final batch, and old responses arriving after a new search. Pagination observes refresh state in its own footer view; observing it in the view that owns refresh hid the native spinner on iOS 26.5. Discovery uses one lazy stack; nesting it inside a regular stack caused scrolling to hang during layout on iOS 26.5.

Account tests use real Keychain entries with unique test service names, plus HTTP fixtures for the authentication endpoints. UI tests sign in, show and hide a password without losing it, relaunch, sign out, and retry incorrect credentials; successful test journeys sign out to remove their saved token. State tests verify credentials and bearer headers, session expiry, retry after transient failures, and local sign-out when server revocation fails. Test-session namespaces are excluded from Release builds and never read the normal app session.

Artwork tests send PNG bytes through an HTTP fixture and verify visible image pixels in cards and details. Missing images, failed requests, and unreadable image data retain the event-type illustration. A malformed image URL does not prevent the event from loading.

The app uses the API’s resolved `image_url`, with `thumbnail_url` retained for older responses. After [backend #430](https://github.com/huddlz-hq/huddlz/issues/430) deployed, live event artwork and the group image fallback were verified in discovery; the group image also appeared in event details on September 7, 2026.

Place-search tests replace Apple’s external Maps search and exercise the real request, map-item conversion, state, and views. UI fixtures use `HUDDLZ_UI_MAP_SCRIPT`; when UI HTTP fixtures are active, place lookup also fails locally on missing fixtures. Both fixture hooks are excluded from Release builds.

Venue-map UI tests control the external place lookup, render the native map, and tap the address to launch Apple Maps. They cover unavailable and ambiguous lookups and locations that should have no map action. Swift Testing also verifies the exact place coordinates and encoded address sent to Maps. Map tiles and the Maps app remain system services; assertions do not depend on their live search results or tile imagery.

Current-location UI tests use Apple’s simulated device location and real system permission prompts to verify nearby results and denied access. For unavailable-location recovery, the `HUDDLZ_UI_LOCATION_FAIL_FIRST` fixture fails one external Core Location request; the retry uses the real service. This hook requires HTTP fixtures and is excluded from Release builds.

## Continuous integration

GitHub Actions runs the full native test suite for pull requests into main and pushes to main. You can also start it from Actions → iOS tests → Run workflow.

Simulator builds use ad-hoc signing so tests can exercise the real Keychain. Disabling signing prevents Keychain access; no signing certificates or developer team are required for these simulator tests.

The workflow uses Xcode 26.6 and an iPhone 17 simulator running iOS 26.5 on a macOS 26 runner. It uses the shared Huddlz scheme and requires no signing certificates or production credentials. Runner availability is listed in [GitHub’s macOS image documentation](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md).

Open the Native behavior tests check on a PR to see the logs. Each run saves an ios-test-results artifact for seven days, including the build log and an .xcresult bundle you can open in Xcode.
