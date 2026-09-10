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

Browse real huddlz in cards with small “Going” or “Waitlisted” badges when signed in; cards without an RSVP stay unmarked. Badges refresh on app return, pull-to-refresh, and as cards enter view, and disappear after sign-out. Submit text with the keyboard’s Search action, and filter by event type (all, in person, online, hybrid) and date (all upcoming, this week, this month). Clear the search field to reset the text query. Pull to refresh while keeping the current cards visible. A failed refresh keeps the cards and filters and offers retry. Bottom search uses a native UIKit search bar: in this layout on iOS 26.5, SwiftUI’s searchable integration detaches the refresh control. Keeping search separate preserves native pull-to-refresh feedback. Scroll near the last card to load the next batch. A bottom spinner shows progress; a failed batch keeps the cards and offers retry. Loading stops after the final batch. Opening a card fetches current details separately. Event times display in the event’s time zone. Details show the hosting group beneath the title. Tap it to read the group’s description and location and browse its upcoming huddlz. Native back navigation returns through the group to the original huddl. Empty lists explain that no upcoming huddlz are scheduled; failed requests offer retry. Load more adds the next batch without removing existing cards. Missing or withheld host information leaves the rest of the details available without a host row. Signed-in details show whether you are going, waitlisted, or have not RSVP’d. The status refreshes when details open or the app becomes active, including changes made on the website. Anonymous browsing shows no personal-status claim. Failed or unreadable status requests keep the event visible with retry.

Online and hybrid details offer “Join online” when the API grants access to a joining link. The server limits access to confirmed attendees and group organizers. Signed-out visitors see an explanation; a missing link leaves the section without an action. Returning to the app checks access again, and signing out removes the link. Failed requests keep the huddl visible and offer retry.

In-person and hybrid details show a native map when Apple Maps resolves the venue to one result. Tap the address row to open that place in Maps and choose directions. The API currently supplies location text without coordinates; failed, empty, or ambiguous lookups keep the address available as a Maps search. Online events and unannounced locations have no map action. A separate live check on September 7, 2026 resolved both the DOS Coffee address in St. Augustine and the Jacksonville Beach venue to one place in Apple Maps.

Choose Anywhere to search for a city or postal code with Apple Maps. Select a place, then choose a distance of 5, 10, 25, 50, or 100 miles. Clear location returns to browsing anywhere and keeps the event search and filters. Place searches run when submitted. Use current location requests location access only after you choose that action, then uses a single fix to find nearby huddlz. Denied access or an unavailable location leaves manual place search available. Leaving the picker cancels a pending lookup.

The client uses anonymous, cookie-free requests to the public JSON API:

- `GET /api/json/huddlz` with `date_filter`, `query`, `event_type`, `search_time_zone`, and `page[limit]`.
- `GET /api/json/huddlz/{id}?include=group&fields[group]=name` for details and the hosting group.
- `GET /api/json/groups/{id}` for the public group profile.
- `GET /api/json/huddlz/by_group?group_id={id}&page[limit]=20` for upcoming published group huddlz, ordered by start time.
- Pagination follows same-origin links returned by the API, restricted to the discovery route or the same group.
- Location searches add `search_latitude`, `search_longitude`, and `distance_miles`. Relative date filters use the selected place’s time zone when available, otherwise the device’s time zone.

Schema: https://huddlz.com/api/json/open_api; browser docs: https://huddlz.com/api/json/swaggerui. Verified September 8, 2026: the deployed schema exposes field sorting without the former duplicate `sort` parameter, and `sort=starts_at` returns HTTP 200. The app uses default ordering. Group discovery remains separate work. Missing thumbnails use an event-type illustration; unavailable host/attendance data is not invented.

Design reference: `prototype/issue-1-core-journey`, variant A (cards). The prototype and simulated account/RSVP flow remain on that branch.

## Accounts

Open Account from discovery to sign in with an existing Huddlz account. Successful sign-in uses the profile city unless a location or Anywhere has already been chosen for this search; text and other filters stay in place. Compact account sheets use persistent field labels, a show-password control, and a prominent sign-in button. They expand for the keyboard and accessibility text sizes. The signed-in sheet groups initials, name, and email above sign-out. “Forgot password?” submits the email to the existing reset API, shows confirmation or a retryable error, and preserves the email on return to sign-in. The emailed link opens huddlz.com to choose a new password. “Create an account” submits a display name, email, password, password confirmation, and explicit acceptance of the linked legal documents. Registration saves the session, then offers an optional home-city step. Rejected forms keep entries available for correction. Upcoming plans and profile editing remain follow-up work under #4–#5.

After signup, choose a city, use current location, or select “Not now.” Location access is requested only after tapping that action. A detected location is resolved to a city center and shown for confirmation; the GPS fix is not saved as home. Confirming saves the city, coordinates, and time zone through the authenticated GraphQL `updateHomeLocation` mutation at `POST /gql`, then applies that city to the current search without clearing other filters. Failed saves keep the selection with retry and skip available. Later sign-ins and app launches read the current profile defaults again.

Authentication uses the dedicated JSON endpoints `POST /api/auth/register`, `POST /api/auth/sign_in`, `GET /api/auth/me`, and `DELETE /api/auth/sign_out`. Requests are cookie-free and do not follow redirects. Only the bearer token is saved, using device-only Keychain storage accessible while unlocked. Sign-in passwords are cleared after submission. Registration keeps passwords in memory for correction after a rejected request and clears them when the form is left or registration succeeds. The app checks a saved session on launch and when it returns to the foreground; expired sessions are removed, while temporary failures offer retry. Sign-out removes the local token before attempting server revocation, with clear feedback if the server cannot be reached. Public discovery remains available without an account.

Search badges use authenticated sparse requests to `GET /api/json/huddlz`, with `date_filter=all`, `fields[huddl]=attendance_state`, and repeated `filter[id][in][]` parameters for visible cards. Requests contain at most 20 IDs, combine brief visibility changes during scrolling, and use the account client’s redirect policy. Public search and pagination stay anonymous. Failed badge requests clear stale badges while keeping cards available; refresh or scrolling retries the lookup.

Personal RSVP status uses a separate authenticated `GET /api/json/huddlz/{id}?fields[huddl]=attendance_state` request. It sends the saved bearer token through the account client’s cookie-free session and rejects redirects. Public event requests stay anonymous. Status remains in memory; account changes and cancelled requests cannot apply a previous account’s response. Event details support RSVP, cancellation, and leaving an existing waitlist. Signing in returns to the same event to finish the RSVP. Pending requests disable the action; failures keep the current status and allow retry. Cancelled, completed, draft, and past events explain that RSVPs are closed. Full-event and other readable API rejections appear beside the action. Successful changes refresh joining access and search badges. The upcoming-plans screen and waitlist enrollment remain separate work under #4.

The authenticated `GET /api/json/profile` endpoint supplies the current home city, coordinates, time zone, and default radius. The app keeps this information in memory and requests it again after sign-in or session restoration on a new launch. An explicit place or Anywhere takes precedence, including when the profile response arrives late. Missing or failed profile data leaves unrestricted discovery and manual location search available. Search overrides do not change the saved profile or request device location permission.

The registration API still returns internal multiline exception descriptions for some validation failures (verified with an empty, rejected request on September 8, 2026). The app displays concise API messages when available and uses plain fallback feedback for internal or unreadable responses. Validation rules and confirmation email delivery remain backend responsibilities. Live checks did not create an account or send email.

## Behavior tests

Run the full local suite with `./scripts/test-behaviors.sh`. It uses four simulator workers, keeps build products between runs, and prints the elapsed time and paths to the log and result bundle. No tests are excluded. Use `HUDDLZ_TEST_WORKERS=2 ./scripts/test-behaviors.sh` on a Mac with less CPU or memory. Override `HUDDLZ_TEST_DESTINATION` or `HUDDLZ_TEST_DERIVED_DATA` when needed.

For focused work, pass Xcode test selections: `./scripts/test-behaviors.sh -only-testing:HuddlzUITests/RSVPUITests` or `./scripts/test-behaviors.sh -only-testing:HuddlzTests/RSVPBehaviorTests`. Command-U also runs the full suite; the shared scheme allows parallel UI execution. Discovery journeys are split into browsing, pagination/refresh, location, venue, and artwork classes so Xcode can distribute them independently. Registration, manual city selection, and location-permission journeys also have separate classes. Test names describe the behavior they protect.

Measured locally on September 10, 2026 with Xcode 26.6, iOS 26.5, and reused build products: the previous serial full run took 18m49s; two workers took 9m40s; two four-worker runs took 5m36s and 5m37s. Each full run passed 110 tests / 149 executions with no skips. The final command keeps every test, including launch performance and UI-configuration checks. A cold build or a Mac with fewer resources will take longer.

UI tests pass a response script through `HUDDLZ_UI_HTTP_SCRIPT`. The debug build uses it only at the HTTP boundary; requests, decoding, state, and views remain real. A missing or invalid scripted response fails locally instead of contacting production. Release builds exclude this hook.

State timing tests hold and release responses explicitly, so cancellation and overlapping searches do not depend on sleeps. Refresh tests cover retained cards, failure, cancellation, and a newer search superseding a pending refresh. A native pull gesture verifies visible cards, preserved filters, and retry after failure. A visual test delays the HTTP response and captures the native spinner during refresh; restoring the conflicting search integration makes this test fail. Keep live API smoke checks separate from this deterministic suite.

Pagination tests scroll through real cards and verify bottom progress, stable scroll position, explicit retry, and continued loading through a repeated batch. State tests cover overlapping requests, the final batch, and old responses arriving after a new search. Pagination observes refresh state in its own footer view; observing it in the view that owns refresh hid the native spinner on iOS 26.5. Discovery uses one lazy stack; nesting it inside a regular stack caused scrolling to hang during layout on iOS 26.5.

Account tests use real Keychain entries with unique test service names, plus HTTP fixtures for the authentication endpoints. Dedicated UI tests sign in, show and hide a password without losing it, relaunch, sign out, retry incorrect credentials, request password resets with confirmation and error recovery, and register with explicit legal acceptance, correction, and session restoration; successful test journeys sign out to remove their saved token. State tests verify credentials and bearer headers, session expiry, retry after transient failures, and local sign-out when server revocation fails. When sign-in is only a precondition, `launchWithSavedSession()` seeds a real token in the isolated test Keychain and uses normal account restoration. The helper removes the seed from subsequent launch environments, so reopening after sign-out cannot silently recreate a session. Sign-in, registration, and sign-in detour journeys still use their real forms. Test-session namespaces and session seeding are excluded from Release builds and never read the normal app session. Account completion waits allow up to 60 seconds and return as soon as the expected UI appears. CI diagnostics showed real Simulator Keychain saves and deletions taking tens of seconds; short UI deadlines failed while those operations were still running. A delayed HTTP response reproduced the original timeout during diagnosis; routine tests keep responses immediate. These behavior checks verify completion, not Keychain speed.

Artwork tests send PNG bytes through an HTTP fixture and verify visible image pixels in cards and details. Missing images, failed requests, and unreadable image data retain the event-type illustration. A malformed image URL does not prevent the event from loading.

The app uses the API’s resolved `image_url`, with `thumbnail_url` retained for older responses. After [backend #430](https://github.com/huddlz-hq/huddlz/issues/430) deployed, live event artwork and the group image fallback were verified in discovery; the group image also appeared in event details on September 7, 2026.

Place-search tests replace Apple’s external Maps search and exercise the real request, map-item conversion, state, and views. UI fixtures use `HUDDLZ_UI_MAP_SCRIPT`; when UI HTTP fixtures are active, place lookup also fails locally on missing fixtures. Both fixture hooks are excluded from Release builds.

Signup-location tests use native permission prompts and simulated device location, with external Maps responses supplied by `HUDDLZ_UI_MAP_SCRIPT` and `HUDDLZ_UI_REVERSE_CITY`. Reverse lookup fixtures require the HTTP test script and never fall through to live lookup. Tests cover confirmation, skipping, city-center coordinates and time zone, failed saves, permission denial, unavailable location, and cancelled lookups. Separate read-only checks on September 8, 2026 confirmed the deployed GraphQL mutation and its inputs; no real profile was changed. Live Maps checks resolved a Kansas City coordinate to a city center and time zone, and manual St. Augustine search returned a complete city. Reverse lookup returned no match for two St. Augustine coordinates; the app leaves manual search and skipping available in that case.

Venue-map UI tests control the external place lookup, render the native map, and tap the address to launch Apple Maps. They cover unavailable and ambiguous lookups and locations that should have no map action. Swift Testing also verifies the exact place coordinates and encoded address sent to Maps. Map tiles and the Maps app remain system services; assertions do not depend on their live search results or tile imagery. Handoff tests allow up to 30 seconds for Maps to enter the foreground and keep it alive between fixture cases, then terminate it at test teardown. CI has delivered its foreground update more than 12 seconds after a tap; short launch deadlines can fail even when the link works. A failed handoff saves a screenshot.

Current-location UI tests use Apple’s simulated device location and real system permission prompts to verify nearby results and denied access. For unavailable-location recovery, the `HUDDLZ_UI_LOCATION_FAIL_FIRST` fixture fails one external Core Location request; the retry uses the real service. This hook requires HTTP fixtures and is excluded from Release builds.

Profile-default tests cover sign-in, relaunch with a changed profile city, explicit location precedence, missing and failed profiles, and signing out during a pending profile request. Held HTTP responses make race tests deterministic. UI tests verify nearby cards, the city and radius controls, and clearing the location. Separate read-only checks verified the deployed profile route rejects anonymous access with 403; authenticated response handling is tested against the documented contract with fixtures, without reading or changing a real profile.

Host behavior tests open a card through the real request, decoding, and UI. They check the matching group name and details with missing or withheld host information. Group UI tests cover opening the host, opening another huddl and returning, empty lists, unavailable groups, and retrying initial and later huddl batches. Separate read-only checks on September 9, 2026 returned HTTP 200 for a public group and its 16 upcoming huddlz. No account or profile was changed.

Attendance behavior tests cover confirmed, waitlisted, and absent RSVPs after sign-in and relaunch, refresh after a background change, retry while preserving public details, and no status claim while signed out. Native Keychain storage and real decoding remain in the path. Held HTTP responses cover sign-out races; malformed or mismatched responses must report errors instead of an absent RSVP. Separate read-only checks on September 9, 2026 verified the deployed schema and anonymous `attendance_state` response. Authenticated behavior uses fixtures; no real RSVP was read or changed.

Search-badge tests cover going, waitlisted, and unmarked cards, foreground and pull-to-refresh updates, sign-out, stale-response rejection, failed refresh recovery, and bounded batch requests. HTTP fixtures preserve repeated query parameters for ID arrays. Separate read-only checks on September 9, 2026 verified that the deployed sparse search endpoint accepts the ID-array filter; no real RSVP was read or changed.

## Continuous integration

GitHub Actions runs the full native test suite for pull requests into main and pushes to main. Four independent macOS runners each use one Simulator with serial test execution. `scripts/ci-test-selection.py` assigns classes to accounts, RSVP/discovery, location/joining, and remaining. The remaining group runs the Swift integration target and everything not assigned to another group, so future tests are included automatically. Duplicate class assignments are rejected.

The groups were balanced using main's CI run 34439192628: roughly 392–404 seconds of UI test execution per group, before runner setup and build time. Rebalance from recorded timings as the suite grows. Each group must run tests, pass, and report no skips. The required “Native behavior tests” check passes only when all four groups succeed. You can also start it from Actions → iOS tests → Run workflow.

Simulator builds use ad-hoc signing so tests can exercise the real Keychain. Disabling signing prevents Keychain access; no signing certificates or developer team are required for these simulator tests.

The workflow uses Xcode 26.6 and an iPhone 17 simulator running iOS 26.5 on a macOS 26 runner. It uses the shared Huddlz scheme and requires no signing certificates or production credentials. Runner availability is listed in [GitHub’s macOS image documentation](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md).

Open any Behavior tests group on a PR to see its Xcode logs. Each group saves an `ios-test-results-<group>` artifact for seven days, including the build log, test summary, and an `.xcresult` bundle you can open in Xcode.

Joining integration tests cover opening the system browser, hybrid organizer access without an RSVP, revoked access on app return, sign-out, retry, and the absence of an online section for in-person events. Held HTTP responses verify sign-out discards a pending link; malformed URLs and responses for another huddl cannot produce an action. The client requests `visible_virtual_link` through an authenticated, cookie-free sparse detail request and accepts absolute HTTP(S) URLs. Separate read-only checks on September 9, 2026 verified the deployed schema and a null link in an anonymous response. No real private joining link was fetched or opened.

RSVP integration tests cover the native sign-in detour, RSVP/cancellation, leaving an existing waitlist, pending requests, full and failed requests, closed events, joining access, and search badges. Swift Testing exercises real requests and Keychain sessions, including expired sessions, old responses after a fresh sign-in, and a status read completed after a successful RSVP. Live checks for this change read only the deployed OpenAPI contract; no real attendance was changed.

Use the current product names and deployed API routes. The backend refactor removed the old “my-” naming; do not introduce that prefix in new UI, documentation, or assumed API paths. Upcoming plans belong to the regular huddlz experience.
