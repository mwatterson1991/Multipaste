import AppKit
import QuartzCore

/// The number that appears beside the pointer when a copy joins the stack.
final class CursorCount {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private static let side: CGFloat = 30
    private var pendingFade: DispatchWorkItem?

    init() {
        let side = CursorCount.side
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: side, height: side),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        // Above the right-click menu that "Copy Image" was just chosen from.
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        // Panels hide when their app isn't active, and this app never is.
        panel.hidesOnDeactivate = false

        let box = NSView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.black.cgColor
        box.layer?.cornerRadius = 7
        // Keeps the black square visible over dark pages.
        box.layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
        box.layer?.borderWidth = 1

        label.font = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: box.centerYAnchor),
        ])
        panel.contentView = box
    }

    func show(_ count: Int) {
        let side = CursorCount.side
        label.stringValue = "\(count)"
        let width = max(side, label.intrinsicContentSize.width + 16)
        panel.setContentSize(NSSize(width: width, height: side))

        // Below and to the right of the pointer, where it doesn't cover what was just copied.
        let pointer = NSEvent.mouseLocation
        var origin = NSPoint(x: pointer.x + 14, y: pointer.y - side - 14)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) {
            origin.x = min(origin.x, screen.frame.maxX - width - 4)
            origin.y = max(origin.y, screen.frame.minY + 4)
        }
        panel.setFrameOrigin(origin)

        pendingFade?.cancel()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        let fade = DispatchWorkItem { [weak self] in
            self?.fadeOut()
        }
        pendingFade = fade
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: fade)
    }

    private func fadeOut() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self = self, self.panel.alphaValue == 0 else { return }
            self.panel.orderOut(nil)
        })
    }
}
