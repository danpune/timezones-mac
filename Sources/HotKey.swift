import AppKit
import Carbon.HIToolbox

// ⌃⌥T opens and closes the panel from any app. A Carbon hot key needs no Accessibility permission.
enum HotKey {
    static var action: (() -> Void)?
    private static var ref: EventHotKeyRef?
    private static var handler: EventHandlerRef?

    static func register() {
        guard ref == nil else { return }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKey.action?() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x545A_4E53), id: 1)   // "TZNS"
        RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
    }

    static func unregister() {
        if let r = ref { UnregisterEventHotKey(r) }
        ref = nil
    }

    /// There is no public API to open a MenuBarExtra, so click its status item button.
    static func togglePanel() {
        NSApp.activate(ignoringOtherApps: true)
        for w in NSApp.windows where String(describing: type(of: w)).contains("StatusBar") {
            if let b = button(in: w.contentView) { b.performClick(nil); return }
        }
    }

    private static func button(in v: NSView?) -> NSStatusBarButton? {
        guard let v else { return nil }
        if let b = v as? NSStatusBarButton { return b }
        for s in v.subviews { if let b = button(in: s) { return b } }
        return nil
    }
}
