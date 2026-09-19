# Time Zones for Mac

A native macOS menu bar app for the [Time Zones](https://danpune.github.io/timezones/) site.
Pinned cities sit next to the macOS clock (`MUM 9:42 AM`); click it for every city as a tile
coloured by that city's real sky, the hours everyone is awake or at work, and a slider to plan a time.

- SwiftUI `MenuBarExtra`, no Dock icon, macOS 13 or later, Apple silicon and Intel
- Same sun maths and sky colours as the website; ~6,300 searchable cities (GeoNames, CC BY 4.0)
- Click a tile to show or hide that city in the menu bar; **Edit cities** to add, rename, reorder, remove
- Weather per city from Open-Meteo (free, CC BY 4.0), °F or °C, one request for all cities, hourly
- Clock-change warning, pick a day and type a time ("3pm"), Copy times for messages
- 12h / 24h, open at login (asked once), ⌃⌥T opens the panel from any app
- Only the weather needs the internet; no accounts, no tracking

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
