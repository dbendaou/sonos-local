# Sonos Local

A native, local-only Sonos controller for macOS.

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111)](https://github.com/dbendaou/sonos-local)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-111111?logo=swift&logoColor=white)](https://swift.org)
[![MIT](https://img.shields.io/badge/license-MIT-111111)](LICENSE)
[![Local only](https://img.shields.io/badge/local--only-no%20cloud-111111)](#what-the-local-api-cannot-do)

<p align="center">
  <img alt="Sonos Local, with the main window and the menu bar popover" src="docs/hero.png" width="1200">
</p>

It replaces the old Sonos desktop app on Apple Silicon: discovery, playback, volume, grouping, queue, favorites, and the settings the speakers expose locally. There is no Sonos account, no telemetry, and no server in the middle.

The window follows the current Sonos iOS app: large artwork, quiet type, room cards, and plenty of space. The menu bar is a full controller. Run it beside the Dock, or as a menu-bar-only app.

Sonos Local is an independent project. It is not affiliated with Sonos, Inc.

## What it does

- Finds speakers with SSDP (`ZonePlayer:1` on `239.255.255.250:1900`) and, on macOS, Bonjour `_sonos._tcp`.
- Reads the household from `GetZoneGroupState` and shows rooms as cards. Bonded subs, surrounds, and the right side of a stereo pair stay hidden.
- Now playing: artwork, title, artist, album, source, play / pause / next / previous, seek, shuffle, repeat, crossfade, sleep timer.
- Group volume and mute on the coordinator, plus each room’s own volume when you group.
- Group and ungroup rooms. Leaving with the coordinator still selected hands coordination to another room first.
- Queue: play a row, reorder, remove, clear.
- Library sheet: Sonos favorites (`FV:2`), playlists (`SQ:` and `A:PLAYLISTS`), line-in and TV (`AI:`), saved radio (`R:0/0`). Play, play next, or add to the queue.
- Room settings read from the speaker: name, bass, treble, loudness, fixed output, Trueplay on/off, night mode, speech enhancement, surround and sub levels, height, audio delay, status light, button lock, alarms, and system info.
- Event subscriptions on AVTransport, RenderingControl, and ZoneGroupTopology, with polling underneath so a missed notify doesn’t freeze the UI.
- Menu bar popover: artwork, transport, volume, and room switching. Settings → **Menu bar only** hides the Dock icon (`LSUIElement`-style activation policy) and keeps the popover.

Album art is loaded from the speaker. If the metadata points at a public CDN, the app asks the speaker’s `/getaa` proxy instead of fetching that host itself.

## What the local API cannot do

These need the official mobile app or a Sonos account. They are not stubbed, and they are not going to be added by calling out to the cloud.

| Not available here | Why |
| --- | --- |
| Sign in to Spotify, Apple Music, Amazon Music, and other services | OAuth and service sessions are cloud flows. |
| Browse a service catalog | SMAPI browsing needs the service session stored for the household and often leaves the LAN. |
| Create a Trueplay tuning | The measurement uses the phone microphone. An existing tuning can be enabled or disabled locally (`SetRoomCalibrationStatus`). |
| Voice assistant setup | Account linking. |
| Firmware updates | The player downloads them from Sonos. |
| Register a system or manage a Sonos account | Cloud only. |
| Stereo-pair and surround bonding | The calls exist (`CreateStereoPair`, `AddHTSatellite`) but a mistake hides a speaker. They are intentionally not in the UI. |

Speakers will still play services that are already linked. Favorites, playlists, the queue, line-in, and TV use the URI the speaker already knows.

## Requirements

- macOS 14 or later, including macOS 26. Apple Silicon or Intel.
- Swift 6 or later if you use Command Line Tools only. A full Xcode install is optional. Apple Swift 6.4 works.
- Speakers on the same LAN as the Mac, reachable on port 1400

The app’s deployment target is macOS 14. Swift 6 would otherwise compile it for macOS 12, which cannot see the SwiftUI APIs it uses.

The protocol module has no Apple-only dependencies, so `swift test` also runs on Linux.

### Command Line Tools

Command Line Tools can build and test this project. Two things about that install matter:

- Tests use [Swift Testing](https://swiftpackageindex.com/swiftlang/swift-testing) (`import Testing`). The CLT toolchain does not ship XCTest, and its Testing macros live under `usr/lib/swift/host/plugins/testing`. `make test` passes that directory as `-plugin-path` when Command Line Tools are selected. Full Xcode finds the plugin on its own.
- `make app` ad-hoc signs the bundle as `com.sonoslocal.mac`, the same identifier as the bundle. macOS stores the Local Network grant against that signature. If speakers never appear, check System Settings → Privacy & Security → Local Network, and watch `log stream --predicate 'subsystem == "com.sonoslocal.mac"'`. Saved speakers are contacted at `http://ip:1400` on the next launch. Settings can forget them or add one by IP.
- The CLT package can default to a macOS SDK newer than the system you are running. On macOS 26.7 the default is `MacOSX27.0.sdk`, and that SDK’s SwiftUI macros are not in the CLT plugin folder (`SwiftUIMacros.StateMacro` / plugin for module `SwiftUIMacros` not found). `MacOSX26.5.sdk` on the same machine builds. `make test`, `make build`, and `make app` notice when `xcrun --show-sdk-version` is newer than the running macOS and switch to an SDK whose major version matches (`xcrun --sdk macosx26.5 --show-sdk-path` in that example). A default SDK at or below the running OS, which is what full Xcode provides, is left alone. Set `SDKROOT` to choose a path yourself.

## Build and run

Open `Package.swift` in Xcode and run the `SonosLocal` scheme.

From the terminal, on a Mac:

```bash
make test
make build
make app
open "build/Sonos Local.app"
```

`make` is the Command Line Tools path. A plain `swift build` uses whatever SDK `xcrun` defaults to, so on the macOS 26 CLT install set the SDK first:

```bash
export SDKROOT="$(xcrun --sdk macosx26.5 --show-sdk-path)"
swift test
swift build --product SonosLocal
```

The first launch on macOS may ask for local network access. That permission is what lets SSDP and Bonjour see speakers. Control traffic is HTTP to the speaker on port 1400 only.

### Menu bar

Sonos Local → Settings → Menu Bar, or the gear in the main window. Settings is also Command-comma.

**Show menu bar item** adds or removes the menu bar icon immediately. Turning it off leaves the Dock icon and the window in place.

**Menu bar only** hides the Dock icon and closes the main window. The menu bar icon still has playback, volume, and rooms. **Open window** brings the window back without turning the Dock icon on. This switch stays off while the menu bar item is hidden, so both cannot be turned off together.

## Project layout

```
Sources/SonosKit     SSDP, SOAP, device and zone XML, DIDL, events, speaker calls
Sources/SonosApp     SwiftUI window, menu bar, settings
Tests/SonosKitTests  Protocol tests, including a loopback event-server test
Scripts/build-app.sh Wraps the release binary in Sonos Local.app
```

`SonosKit` is the boundary. The app never builds SOAP itself.

## Design

Light mode is white. Dark mode is black. Room cards are soft gray rectangles with the room name, what’s playing, and a small piece of art. The now-playing column is a single large cover, a thin scrubber, a circular play button, and a thin volume slider. Controls that aren’t needed for the current gesture stay quiet.

The menu bar uses the same pieces at a smaller size, with the room list under the transport.

## Development

```bash
swift test
```

CI is `.github/workflows/ci.yml`. It runs on `macos-14`, tests the protocol module, and builds `SonosLocal`.

If you change an action, a parser, or a URI, add a fixture in `Tests/SonosKitTests`. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Verification

Protocol tests cover XML, SOAP envelopes and faults, device descriptions, zone groups (including the escaped XML Sonos returns), DIDL metadata, event `LastChange`, alarms, SSDP responses, play-mode mapping, seek time formatting, queue reorder indexes, local-only artwork URLs, and the notify server on loopback.

Playback against real speakers was not run in the environment that produced this tree (it is not a Mac, and there is no speaker on its network). On a Mac, `make test`, `make build`, and `make app` are the checks to run, then point the app at a household. With Command Line Tools, use those Make targets so the SDK matches the running macOS.

## License

[MIT](LICENSE)
