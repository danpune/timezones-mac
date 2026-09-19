import SwiftUI

@main
struct TimeZonesApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        MenuBarExtra {
            Panel().environmentObject(store)
        } label: {
            // Pinned cities sit next to the macOS clock, e.g. "MUM 9:42 AM"; with none pinned, a globe.
            let title = store.menuTitle
            if title.isEmpty { Image(systemName: "globe") } else { Text(title).monospacedDigit() }
        }
        .menuBarExtraStyle(.window)
    }
}
