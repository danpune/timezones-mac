import AppKit
import Combine
import SwiftUI

/// The menu bar item and its panel, built on NSStatusItem + NSPopover rather than SwiftUI's
/// MenuBarExtra: on macOS 27 a MenuBarExtra cannot be opened from code, so ⌃⌥T and Esc did nothing.
@MainActor
final class StatusController: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    static private(set) weak var shared: StatusController?
    let store = Store()
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var changes: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ note: Notification) {
        StatusController.shared = self
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(clicked)
        let host = NSHostingController(rootView: Panel().environmentObject(store))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        popover.delegate = self
        store.panelShown = { [weak self] in self?.popover.isShown ?? false }
        for source in [store.objectWillChange, Updater.shared.objectWillChange] {
            source.sink { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }.store(in: &changes)
        }
        refresh()
        Updater.shared.idle = { [weak self] in !(self?.popover.isShown ?? true) }
        Updater.shared.checkIfDue()
    }

    /// Pinned cities next to the macOS clock ("🇮🇳 MUM 9:42a"); a globe when none is pinned. A blue dot
    /// after an update, until the panel is opened and the "Updated" line has been seen.
    private func refresh() {
        guard let b = item?.button else { return }
        let t = store.menuTitle(), updated = Updater.shared.updated
        b.image = t.isEmpty ? NSImage(systemSymbolName: "globe", accessibilityDescription: "Time Zones") : nil
        b.attributedTitle = StatusController.title(t, dot: updated != nil)
        b.setAccessibilityLabel((t.isEmpty ? "Time Zones" : "Time Zones, " + store.menuTitle(short: false))
                                + (updated.map { ", updated to version \($0)" } ?? ""))
    }

    static func title(_ text: String, dot: Bool) -> NSAttributedString {
        let size = NSFont.menuBarFont(ofSize: 0).pointSize
        let s = NSMutableAttributedString(string: text, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)])
        if dot {
            s.append(NSAttributedString(string: text.isEmpty ? "●" : " ●",
                                        attributes: [.font: NSFont.systemFont(ofSize: size * 0.62), .foregroundColor: NSColor.systemBlue]))
        }
        return s
    }

    @objc private func clicked() { toggle() }

    func toggle() {
        if popover.isShown { popover.performClose(nil); return }
        guard let b = item.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func close() { if popover.isShown { popover.performClose(nil) } }

    /// Opening the app again from Finder or Spotlight shows the panel: the only way in if the
    /// menu bar item is ever hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { toggle() }
        return false
    }

    func popoverWillShow(_ notification: Notification) { store.panelOpening(); Updater.shared.checkIfDue() }
    func popoverDidClose(_ notification: Notification) { store.panelClosed(); Updater.shared.panelClosed() }
}
