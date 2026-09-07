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

Browse real huddlz in cards, submit text with the keyboard’s Search action, and filter by event type (all, in person, online, hybrid) and date (all upcoming, this week, this month). Clear the search field to reset the text query. Pull to refresh; use Load more when another API page is available. Opening a card fetches current details separately. Event times display in the event’s time zone.

Choose Anywhere to search for a city or postal code with Apple Maps. Select a place, then choose a distance of 5, 10, 25, 50, or 100 miles. Clear location returns to browsing anywhere and keeps the event search and filters. Place searches run when submitted; they do not request access to the device’s current location.

The client uses anonymous, cookie-free requests to the public JSON API:

- `GET /api/json/huddlz` with `date_filter`, `query`, `event_type`, `search_time_zone`, and `page[limit]`.
- `GET /api/json/huddlz/{id}` for details.
- Pagination follows same-origin discovery links returned by the API.
- Location searches add `search_latitude`, `search_longitude`, and `distance_miles`. Relative date filters use the selected place’s time zone when available, otherwise the device’s time zone.

Schema: https://huddlz.com/api/json/open_api; browser docs: https://huddlz.com/api/json/swaggerui. Verified September 6, 2026. The deployed API rejects the documented `sort=soonest`, so the app uses default ordering. Group discovery, authentication, and RSVP remain separate work. Missing thumbnails use an event-type illustration; unavailable host/attendance data is not invented.

Design reference: `prototype/issue-1-core-journey`, variant A (cards). The prototype and simulated account/RSVP flow remain on that branch.

## Behavior tests

Use Command-U in Xcode to run the suite. `HuddlzTests` exercises discovery through its public interface with controlled HTTP responses. `DiscoveryUITests` drives search, filters, details, empty states, and retry in Simulator. Test names describe the behavior they protect.

UI tests pass a response script through `HUDDLZ_UI_HTTP_SCRIPT`. The debug build uses it only at the HTTP boundary; requests, decoding, state, and views remain real. A missing or invalid scripted response fails locally instead of contacting production. Release builds exclude this hook.

Timing tests hold and release responses explicitly, so cancellation and overlapping searches do not depend on sleeps. Keep live API smoke checks separate from this deterministic suite.

Artwork tests send PNG bytes through an HTTP fixture and verify visible image pixels in cards and details. Missing images, failed requests, and unreadable image data retain the event-type illustration. A malformed image URL does not prevent the event from loading.

The app uses the API’s resolved `image_url`, with `thumbnail_url` retained for older responses. After [backend #430](https://github.com/huddlz-hq/huddlz/issues/430) deployed, live event artwork and the group image fallback were verified in discovery; the group image also appeared in event details on September 7, 2026.

Place-search tests replace Apple’s external Maps search and exercise the real request, map-item conversion, state, and views. UI fixtures use `HUDDLZ_UI_MAP_SCRIPT`; when UI HTTP fixtures are active, place lookup also fails locally on missing fixtures. Both fixture hooks are excluded from Release builds.

## Continuous integration

GitHub Actions runs the full native test suite for pull requests into main and pushes to main. You can also start it from Actions → iOS tests → Run workflow.

The workflow uses Xcode 26.6 and an iPhone 17 simulator running iOS 26.5 on a macOS 26 runner. It uses the shared Huddlz scheme and requires no signing certificates or production credentials. Runner availability is listed in [GitHub’s macOS image documentation](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md).

Open the Native behavior tests check on a PR to see the logs. Each run saves an ios-test-results artifact for seven days, including the build log and an .xcresult bundle you can open in Xcode.
