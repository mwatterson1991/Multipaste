import AppKit
import Carbon.HIToolbox

/// Sees every ⌘V a moment before the app in front does, so the right copy can be put on the pasteboard first.
/// macOS only allows this once Accessibility is switched on for the app.
enum PasteTap {
    private static var onPaste: (() -> Void)?
    private static var port: CFMachPort?

    /// False when macOS refuses, which means Accessibility isn't allowed yet.
    static func start(onPaste: @escaping () -> Void) -> Bool {
        if port != nil { return true }
        PasteTap.onPaste = onPaste

        let keyDown = CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue)
        let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: keyDown,
            callback: { _, type, event, _ in
                // macOS switches a tap off if it ever answers slowly. Switch it straight back on.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let port = PasteTap.port {
                        CGEvent.tapEnable(tap: port, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                let isV = event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_ANSI_V)
                // A held key repeats; only the press itself should move on to the next copy.
                let isFreshPress = event.getIntegerValueField(.keyboardEventAutorepeat) == 0
                // ⌃⌘V is Paste All, handled elsewhere.
                let isPaste = event.flags.contains(.maskCommand) && !event.flags.contains(.maskControl)
                if type == .keyDown && isV && isFreshPress && isPaste {
                    PasteTap.onPaste?()
                }
                // The keystroke itself always goes through untouched.
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        )
        guard let port = created else { return false }

        PasteTap.port = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }
}
