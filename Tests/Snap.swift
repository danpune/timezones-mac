// Renders the panel off-screen to PNGs, so the UI can be checked without screen-recording access.
//   swiftc -swift-version 5 -parse-as-library Sources/{Sky,Places,Store,Views,HotKey,States,StatusController}.swift \
//     Tests/Snap.swift -o build/snap  (then copy Resources/cities.txt and Resources/flags next to it)
import AppKit
import SwiftUI

@main
struct Snap {
    @MainActor static func main() {
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let store = Store()
        print("menu bar title:", store.menuTitle(), "|", store.menuTitle(short: false))
        print("overlap:", store.overlap ?? "-")
        print("search mum:", Catalog.shared.search("mum").map(\.name))
        print("search thailand:", Catalog.shared.search("thailand").map(\.name))
        print("search nel:", Catalog.shared.search("nel").map(\.name))
        store.loadWeather()
        for _ in 0..<40 { RunLoop.main.run(until: Date().addingTimeInterval(0.25)); if store.wx(store.places[0], at: Date()) != nil { break } }
        print("weather:", store.places.map { p in store.wx(p, at: Date()).map { "\(p.name) \($0.temp)° \($0.words)" } ?? "\(p.name) none" })
        func shot(_ name: String, dark: Bool = false) {
            let host = NSHostingView(rootView: Panel().environmentObject(store).background(Color(nsColor: .windowBackgroundColor)))
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let size = host.fittingSize
            host.frame = NSRect(origin: .zero, size: size)
            let win = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            win.contentView = host
            win.backgroundColor = dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.97, alpha: 1)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
            print("wrote \(name).png \(Int(size.width))x\(Int(size.height))")
        }
        shot("1-live")
        shot("2-live-dark", dark: true)
        store.h24 = true; shot("3-24h"); store.h24 = false
        store.setMinuteOfDay(9 * 60, on: Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 27))); shot("4-planning")
        print("clock note:", store.clockNote ?? "-")
        print("times:\n" + store.timesText)
        print("link:", store.websiteURL()?.absoluteString ?? "-")
        print("parse:", ["3pm", "3:30 pm", "15:30", "1530", "9", "25:00", "13pm", "abc"].map { Store.parseTime($0).map(String.init) ?? "nil" })
        store.planned = nil
        store.query = "san"; shot("5-search")
        print("search pst:", Catalog.shared.search("pst").map { $0.name + " " + $0.zone })
        print("search ist:", Catalog.shared.search("ist").prefix(2).map { $0.name + " " + $0.zone })
        print("search utc:", Catalog.shared.search("utc").prefix(1).map { $0.name + " " + $0.zone })
        store.query = ""; store.editing = true; shot("5b-editing")
        store.hoverID = store.places[1].id; store.editing = false; shot("5c-hover"); store.hoverID = nil
        store.editing = false; store.query = ""
        let before = store.places.map(\.name)
        store.drag(store.places[4].id, by: -100)   // London up two rows, still held
        shot("6-dragging")
        print("while dragging:", store.places.map(\.name), "offset", store.dragOffset)
        store.endDrag()
        store.drag(store.places[0].id, by: 400)    // first row past the end clamps to last
        store.endDrag()
        print("before:", before, "\nafter:", store.places.map(\.name))
        // Many cities, long names, 24h and Celsius, question answered
        store.askLogin = false
        for q in ["Santiago de Queretaro", "Tokyo", "Sydney", "Reykjavik"] { if let p = Catalog.shared.search(q).first { store.add(p) } }
        store.loadWeather()
        for _ in 0..<40 { RunLoop.main.run(until: Date().addingTimeInterval(0.25)); if store.places.allSatisfy({ store.wx($0, at: Date()) != nil }) { break } }
        store.note = nil
        shot("7-nine-cities")
        store.h24 = true; store.fahrenheit = false; shot("8-24h-celsius-dark", dark: true)
    }
}
