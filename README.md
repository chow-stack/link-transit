# Link: Bloomington Transit Tracker

**A fast, native iOS app for riding Bloomington Transit: live bus locations, real-time arrivals, service alerts, and arrival reminders, all on one map.**

Link combines Bloomington Transit's public GTFS schedule with its GTFS-Realtime feeds. Riders can see where every bus is right now, when the next one reaches their stop, and whether anything is disrupting service. It needs no account and has no ads or tracking.

![Swift](https://img.shields.io/badge/Swift-5-f05138) ![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0a84ff) ![iOS](https://img.shields.io/badge/iOS-17%2B-black) ![License: MIT](https://img.shields.io/badge/license-MIT-blue)

> Link is an independent project. It is not affiliated with or endorsed by Bloomington Transit.

---

## Contents

- [Features](#features)
- [Architecture](#architecture)
- [Getting started](#getting-started)
- [Updating transit data](#updating-transit-data)
- [Adapting Link to another transit agency](#adapting-link-to-another-transit-agency)
- [Project structure](#project-structure)
- [Privacy](#privacy)
- [License](#license)

## Features

- **Live map.** Bus positions refresh every 15 seconds on MapKit, with route shapes, stops, and route color badges.
- **Real-time arrivals.** Stop sheets combine GTFS-Realtime trip updates with the static schedule, so you get live ETAs where available and scheduled times where not.
- **Route filter.** Show only the routes you ride.
- **Service alerts.** A banner and detail sheet for active disruptions, refreshed every minute.
- **Arrival reminders.** Local notifications before a bus reaches a chosen stop.
- **Favorites.** Saved stops, persisted with SwiftData.
- **Service hours.** Per-route operating hours based on the service calendar.
- **Directions.** Hand-off to Apple Maps or Google Maps, with a remembered preference.
- **On-demand booking.** An in-app link to the agency's on-demand ride service.
- **Resilient networking.** Fast timeouts, exponential-backoff retries, offline detection, and a network status banner. Bundled schedule data keeps stops, routes, and timetables available offline.
- **Polish.** Onboarding, light and dark themes, loading shimmer, and an in-app privacy policy.

## Architecture

```
                 ┌─────────────────────────────┐
Bundled JSON ──▶ │ StaticDataService            │  routes, stops, trips, shapes,
(from GTFS ZIP)  │ StopTimesService             │  stop times, service calendar
                 └──────────────┬──────────────┘
                                │ trip_id join
                 ┌──────────────▼──────────────┐
GTFS-Realtime ─▶ │ GTFSRealtimeService (proto)  │  vehicle positions, trip updates, alerts
(.pb over HTTPS) │ RealtimeETAService           │
                 └──────────────┬──────────────┘
                                ▼
                 MapViewModel / BusInfoViewModel ──▶ SwiftUI views (MapKit)
```

- **Static data** is generated ahead of time from the agency's GTFS ZIP by `Scripts/update_gtfs.py` and bundled in `link/Resources/StaticData/`, so the app launches instantly and works offline.
- **Realtime data** is decoded from Protocol Buffers with [SwiftProtobuf](https://github.com/apple/swift-protobuf). `link/Core/Models/gtfs-realtime.pb.swift` is generated from the official [GTFS-Realtime proto](https://github.com/google/transit/tree/master/gtfs-realtime).
- **Concurrency** uses Swift structured concurrency and actors, with Observation-based view models.
- **No backend.** The app talks only to the agency's public feeds, and it needs no API keys.

## Getting started

### Requirements

- macOS with **Xcode 26** or newer
- iOS 17 or newer (device or simulator)

### Build and run

```bash
git clone https://github.com/chow-stack/link-transit.git
cd link-transit
open link.xcodeproj
```

1. Xcode resolves the SwiftProtobuf package automatically.
2. Select the **link** target → **Signing & Capabilities**, choose your own **Team**, and change the **Bundle Identifier** to one you own (for example `com.yourname.link`).
3. Pick a simulator or device and press **⌘R**.

## Updating transit data

The app joins realtime vehicles to static trips by exact `trip_id`, so all bundled files must come from the same GTFS snapshot. Regenerate them whenever the agency publishes a new schedule:

```bash
python3 Scripts/update_gtfs.py                    # download the latest GTFS ZIP and regenerate
python3 Scripts/update_gtfs.py --zip path/to.zip  # or use a local ZIP
python3 Scripts/test_update_gtfs.py              # run the generator's tests
```

The script uses only the Python standard library.

## Adapting Link to another transit agency

Any agency that publishes GTFS and GTFS-Realtime feeds can work:

1. Point `DEFAULT_GTFS_URL` in `Scripts/update_gtfs.py` at the agency's GTFS ZIP and regenerate the static data.
2. Update the three feed URLs in `link/Core/Networking/APIConfig.swift`.
3. Adjust the initial map region, branding colors in `Assets.xcassets`, and the on-demand booking link.

## Project structure

```
link/
├── LinkApp.swift               App entry point
├── Core/
│   ├── Models/                 GTFS models (Route, Stop, Trip, Vehicle, Alert, ...) and generated protobuf
│   ├── Networking/             API config, client, GTFS-Realtime and ETA services, sync, errors
│   └── Services/               Static data, stop times, alerts, notifications, favorites, location, theme
├── Features/
│   ├── Map/                    Main map, bus and stop sheets, alerts, route filter, service hours
│   ├── Favorites/
│   ├── Notifications/          Arrival reminder setup and management
│   ├── Onboarding/
│   ├── Booking/                On-demand ride booking (in-app Safari)
│   └── Settings/               Preferences and privacy policy
└── Resources/StaticData/       Bundled JSON generated from GTFS
Scripts/                        GTFS → JSON generator and its tests
```

## Privacy

Link has no accounts, analytics, advertising, or cross-app tracking. Location is used only on the device, to center the map and find nearby stops. Favorites, reminders, and preferences are stored locally. The only network requests go to the transit agency's public data feeds. See the full policy in the app under **Settings → Privacy Policy**.

## License

Released under the [MIT License](LICENSE).

Transit data is provided by Bloomington Transit under its own terms. SwiftProtobuf and the GTFS-Realtime proto are licensed under Apache 2.0.
