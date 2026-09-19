# Time Zones for Mac

A native macOS menu bar app for the [Time Zones](https://danpune.github.io/timezones/) site.
Pinned cities sit next to the macOS clock (`MUM 9:42 AM`); click it for every city as a tile
coloured by that city's real sky, the hours everyone is awake or at work, and a slider to plan a time.

- SwiftUI panel in an `NSStatusItem` + `NSPopover` (not `MenuBarExtra`, which can't be opened from code on
  macOS 27), no Dock icon, macOS 13 or later, Apple silicon and Intel. Opening the app again shows the panel.
- Same sun maths and sky colours as the website; ~6,300 searchable cities (GeoNames, CC BY 4.0)
- Click a tile to show or hide that city in the menu bar; **Edit cities** to add, rename, reorder, remove
- Weather per city from Open-Meteo (free, CC BY 4.0), °F or °C, one request for all cities, hourly
- Clock-change warning, pick a day and type a time ("3pm"), Copy times for messages
- 12h / 24h, open at login (asked once), ⌃⌥T opens the panel from any app
- Only the weather needs the internet; no accounts, no tracking

## Install

1. Download **Time-Zones-mac.zip** from the [latest release](https://github.com/danpune/timezones-mac/releases/latest) and double-click it.
2. Drag **Time Zones** into your Applications folder, then open it.
3. macOS says it can't check the app, because it isn't signed with a paid Apple developer account.
   Open **System Settings → Privacy & Security**, scroll down, click **Open Anyway** next to
   "Time Zones", and enter your password. You only do this once for each version.
   ([Apple's guide](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac))
4. The app lives in the menu bar (no Dock icon). ⌃⌥T opens it from any app; opening the app again from
   Spotlight or Finder also shows it.

## Build

Needs only the Xcode Command Line Tools:

```
./build.sh            # builds build/Time Zones.app (ad-hoc signed)
./build.sh install    # also copies it to /Applications and opens it
```

The ad-hoc signature runs on the Mac that built it. To share the app with others it needs a
Developer ID signature and notarization, or the Mac App Store.

`Tests/Snap.swift` renders the panel off-screen to PNGs for checking the UI without screen access.

MIT licensed.
