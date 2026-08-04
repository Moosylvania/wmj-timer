import AppKit
import Carbon.HIToolbox

extension Notification.Name {
    /// Object is a `WindowID` string, or nil for "smart" (Timer if one is
    /// running/stopped, Quick Log otherwise). Received by `MenuBarLabel`.
    static let wmjOpenPanel = Notification.Name("wmjOpenPanel")
}

/// Global shortcuts so the app stays reachable when macOS hides the menu bar
/// icon (notch, crowded status bar): ⌃⌥T → Timer, ⌃⌥L → Quick Log.
/// Carbon hotkeys need no Accessibility permission, unlike NSEvent global monitors.
// ponytail: shortcuts are hardcoded; add a recorder UI only if a real conflict is reported.
enum HotKeys {
    private static let targets: [UInt32: String] = [1: WindowID.timer, 2: WindowID.quickLog]

    static func install() {
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                    eventKind: UInt32(kEventHotKeyPressed))
        // C callback — no captures allowed; HotKeys.targets is a global access, not a capture.
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            if let id = HotKeys.targets[hotKeyID.id] {
                NotificationCenter.default.post(name: .wmjOpenPanel, object: id)
            }
            return noErr
        }, 1, &pressed, nil, nil)

        let signature = OSType(0x574D_4A54)  // "WMJT"
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(controlKey | optionKey),
                            EventHotKeyID(signature: signature, id: 1),
                            GetEventDispatcherTarget(), 0, &ref)
        RegisterEventHotKey(UInt32(kVK_ANSI_L), UInt32(controlKey | optionKey),
                            EventHotKeyID(signature: signature, id: 2),
                            GetEventDispatcherTarget(), 0, &ref)
    }
}
