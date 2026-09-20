import AppKit
import Combine
import SwiftUI

/// The menu bar items and their panel, built on NSStatusItem + NSPopover rather than SwiftUI's
/// MenuBarExtra: on macOS 27 a MenuBarExtra cannot be opened from code, so ⌃⌥T and Esc did nothing.
///
/// One item per pinned city, rather than one wide item for all of them: macOS keeps what fits beside
/// the clock and moves the rest to the other side of the camera, so every city keeps its flag or name.
@MainActor
final class StatusController: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    static private(set) weak var shared: StatusController?
    let store = Store()
    private var items: [NSStatusItem] = []
    private let popover = NSPopover()
    private var changes: Set<AnyCancellable> = []
    private var pins = "-"

    func applicationDidFinishLaunching(_ note: Notification) {
        StatusController.shared = self
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

    /// Each pinned city next to the macOS clock ("🇮🇳 MUM 9:42a"); a globe when none is pinned. A blue dot
    /// on the last one after an update, until the panel is opened and the "Updated" line has been seen.
    private func refresh() {
        let pinned = store.places.filter(\.pinned)
        let key = pinned.map(\.name).joined(separator: "|")
        if key != pins { pins = key; make(pinned.isEmpty ? 1 : pinned.count) }
        let updated = Updater.shared.updated
        guard !pinned.isEmpty else {
            let b = items[0].button
            b?.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "Time Zones")
            b?.attributedTitle = StatusController.title("", dot: updated != nil)
            b?.toolTip = "Time Zones"
            b?.setAccessibilityLabel("Time Zones" + (updated.map { ", updated to version \($0)" } ?? ""))
            return
        }
        for (i, p) in pinned.enumerated() {
            guard let b = items[i].button else { continue }
            b.image = nil
            b.attributedTitle = StatusController.title(store.menuLabel(p), dot: updated != nil && i == pinned.count - 1)
            b.toolTip = p.name + ", " + store.time(p, at: store.now)
            b.setAccessibilityLabel(p.name + ", " + store.time(p, at: store.now)
                                    + (updated.map { ", Time Zones updated to version \($0)" } ?? ""))
        }
    }

    /// Fresh items whenever the pinned cities change. Made back to front: each new item goes to the left
    /// of the ones before it, so they read in the panel's order.
    private func make(_ count: Int) {
        items.forEach(NSStatusBar.system.removeStatusItem)
        items = (0..<count).map { _ in
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = self
            item.button?.action = #selector(clicked)
            return item
        }.reversed()
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

    @objc private func clicked(_ sender: NSStatusBarButton) { toggle(from: sender) }

    func toggle(from button: NSStatusBarButton? = nil) {
        if popover.isShown { popover.performClose(nil); return }
        guard let b = button ?? items.last?.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func close() { if popover.isShown { popover.performClose(nil) } }

    /// Opening the app again from Finder or Spotlight shows the panel: the only way in if the
    /// menu bar items are ever hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { toggle() }
        return false
    }

    func popoverWillShow(_ notification: Notification) { store.panelOpening(); Updater.shared.checkIfDue() }
    func popoverDidClose(_ notification: Notification) { store.panelClosed(); Updater.shared.panelClosed() }
}
