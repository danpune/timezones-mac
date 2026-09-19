// Renders the README screenshots into docs/ from the app's own views (off-screen, @2x).
//   swiftc -swift-version 5 -parse-as-library Sources/{Sky,Places,Store,Views,HotKey,States,StatusController,Updater}.swift \
//     Tests/Screens.swift -o build/screens  (copy Resources/cities.txt and Resources/flags next to it), then run
//   build/screens docs
import AppKit
import SwiftUI

@main
struct Screens {
    @MainActor static func main() {
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        UserDefaults.standard.removePersistentDomain(forName: "screens")
        let store = Store()
        store.askLogin = false
        store.loadWeather()
        for _ in 0..<60 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            if store.places.allSatisfy({ store.wx($0, at: Date()) != nil }) { break }
        }
        func shot(_ name: String, dark: Bool = false) {
            store.note = nil
            let host = NSHostingView(rootView: Panel().environmentObject(store).background(Color(nsColor: .windowBackgroundColor)))
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            let win = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            win.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
            print("wrote \(name).png")
        }
        shot("panel")
        shot("panel-dark", dark: true)
        // plan the next 9 AM: the sky colours, sunrise times and weather follow the planned moment
        let today9 = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        store.setMinuteOfDay(9 * 60, on: today9 > Date() ? Date() : Calendar.current.date(byAdding: .day, value: 1, to: Date()))
        shot("planning")
        store.planned = nil
        store.query = "nel"; shot("search"); store.query = ""
        store.hoverID = store.places[1].id; shot("hover"); store.hoverID = nil
        UserDefaults.standard.removePersistentDomain(forName: "screens")
    }
}
