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

The client uses anonymous, cookie-free requests to the public JSON API:

- `GET /api/json/huddlz` with `date_filter`, `query`, `event_type`, `search_time_zone`, and `page[limit]`.
- `GET /api/json/huddlz/{id}` for details.
- Pagination follows same-origin discovery links returned by the API.

Schema: https://huddlz.com/api/json/open_api; browser docs: https://huddlz.com/api/json/swaggerui. Verified September 6, 2026. The deployed API rejects the documented `sort=soonest`, so the app uses default ordering. Location-radius search, group discovery, authentication, and RSVP are outside this issue. Missing thumbnails use an event-type illustration; unavailable host/attendance data is not invented.

Design reference: `prototype/issue-1-core-journey`, variant A (cards). The prototype and simulated account/RSVP flow remain on that branch.
