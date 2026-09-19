// Renders the panel off-screen to PNGs, so the UI can be checked without screen-recording access.
//   swiftc ... Sources/{Sky,Places,Store,Views}.swift Tests/Snap.swift -o build/snap && build/snap out/
import AppKit
import SwiftUI

@main
struct Snap {
    @MainActor static func main() {
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let store = Store()
        print("menu bar title:", store.menuTitle)
        print("overlap:", store.overlap ?? "-")
        print("search mum:", Catalog.shared.search("mum").map(\.name))
        print("search thailand:", Catalog.shared.search("thailand").map(\.name))
        print("search nel:", Catalog.shared.search("nel").map(\.name))
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
        store.offsetMin = 12 * 60; shot("4-planning")
        store.offsetMin = 0
        store.editing = true; store.query = "nel"; shot("5-editing")
    }
}
