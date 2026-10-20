# Contributing

Sonos Local is a local-network controller. Changes should keep it that way: no Sonos account, no telemetry, and no new dependency on a server you don't run.

## Layout

- `Sources/SonosKit` is the protocol module. It is plain Swift and Foundation, so it builds on Linux and macOS.
- `Sources/SonosApp` is the SwiftUI app. It builds only on macOS 14 or later.
- `Tests/SonosKitTests` covers parsing, SOAP, discovery messages, queue math, and the local event receiver.

## Before you open a pull request

1. Add or update a unit test when you change a parser, SOAP body, or URI.
2. Run `swift test`.
3. On a Mac, run `swift build --product SonosLocal` and launch the app against a speaker if you can.

## Protocol notes

Speakers speak UPnP on port 1400. The useful services are AVTransport, RenderingControl, GroupRenderingControl, ContentDirectory, ZoneGroupTopology, AlarmClock, and DeviceProperties. Embedded XML (zone groups, DIDL, alarms, events) arrives escaped inside SOAP, and has to be decoded before it is parsed again.

Prefer the coordinator for transport, queue, and group volume. Per-room volume, EQ, the status light, and button lock go to that room's own speaker.

Do not add calls to Sonos cloud hosts. Album art that points off the LAN is rewritten through the speaker's `/getaa` proxy.

## Design

The window follows the current Sonos iOS app: white or black canvas, large artwork, quiet type, room cards, and small controls. The menu bar popover is a first-class surface, not a leftover. Keep both in sync through `AppModel`.
