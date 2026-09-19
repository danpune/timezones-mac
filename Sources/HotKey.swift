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

    @MainActor static func togglePanel() { StatusController.shared?.toggle() }
    @MainActor static func closePanel() { StatusController.shared?.close() }
}
