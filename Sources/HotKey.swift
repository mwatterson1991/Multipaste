import Carbon.HIToolbox

/// A system-wide shortcut. Registered this way, the keystroke never reaches the app in front.
final class HotKey {
    private static var action: (() -> Void)?

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        HotKey.action = action

        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        _ = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            HotKey.action?()
            return OSStatus(noErr)
        }, 1, &pressed, nil, &handler)

        // "MPST"
        let id = EventHotKeyID(signature: OSType(0x4D50_5354), id: 1)
        _ = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
    }
}
