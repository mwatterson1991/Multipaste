import AppKit
import Carbon.HIToolbox
import ServiceManagement

/// Wires the pieces together and owns the menu bar item.
final class Controller: NSObject {
    private let stack: ClipStack
    private let watcher: PasteboardWatcher
    private let paster: Paster
    private let cursorCount = CursorCount()

    private var hotKey: HotKey?
    private var statusItem: NSStatusItem?
    private var pasteAllItem: NSMenuItem?
    private var clearItem: NSMenuItem?
    private var accessTimer: Timer?

    override init() {
        let stack = ClipStack()
        let watcher = PasteboardWatcher()
        self.stack = stack
        self.watcher = watcher
        self.paster = Paster(stack: stack, watcher: watcher)
        super.init()
    }

    func start() {
        buildMenu()

        stack.onChange = { [weak self] in
            self?.refresh()
        }
        watcher.onCopy = { [weak self] clip in
            guard let self = self, self.stack.add(clip) else { return }
            // One copy is the ordinary clipboard; the number only has something to say from the second.
            let count = self.stack.clips.count
            Log.note("copied stack=\(count)")
            if count > 1 {
                self.cursorCount.show(count)
            }
        }
        watcher.start()

        // ⌘V pastes the next copy. ⌃⌘V pastes them all at once: next to ⌘V under the same hand, and unused by macOS and Figma.
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | controlKey)) { [weak self] in
            self?.pasteAll()
        }

        waitForAccess()
        Log.note("started")

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(willTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    // MARK: Pasting

    private func pasteAll() {
        guard AXIsProcessTrusted() else {
            askForAccess()
            return
        }
        paster.pasteAll()
    }

    // MARK: Accessibility

    private func askForAccess() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    private func waitForAccess() {
        if watchForPastes() { return }
        askForAccess()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] tick in
            guard let self = self, self.watchForPastes() else { return }
            tick.invalidate()
        }
        RunLoop.main.add(timer, forMode: .common)
        accessTimer = timer
    }

    /// False until Accessibility has been allowed.
    private func watchForPastes() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        return PasteTap.start { [weak self] in
            self?.willPaste()
        }
    }

    /// Runs just before a ⌘V reaches the app in front.
    /// With several copies stacked, each ⌘V gets the next one, oldest first. After the last, ⌘V is ordinary again.
    private func willPaste() {
        guard !paster.isBusy else { return }
        if let next = stack.takeNext() {
            next.write(to: NSPasteboard.general)
            watcher.sync()
        }
        // The next copy after any paste starts a new stack.
        stack.markPasted()
    }

    // MARK: Menu bar

    private func buildMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "square.stack", accessibilityDescription: AppInfo.name)
        item.button?.imagePosition = .imageLeading

        let pasteAll = NSMenuItem(title: "Paste All", action: #selector(pasteAllFromMenu), keyEquivalent: "v")
        pasteAll.keyEquivalentModifierMask = [.control, .command]
        pasteAll.target = self

        let clear = NSMenuItem(title: "Clear", action: #selector(clearStack), keyEquivalent: "")
        clear.target = self

        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off

        let quit = NSMenuItem(title: "Quit \(AppInfo.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp

        let menu = NSMenu()
        // Paste All and Clear are switched off by hand when the stack is empty.
        menu.autoenablesItems = false
        let entries: [NSMenuItem] = [pasteAll, clear, NSMenuItem.separator(), login, NSMenuItem.separator(), quit]
        for entry in entries {
            menu.addItem(entry)
        }
        item.menu = menu

        statusItem = item
        pasteAllItem = pasteAll
        clearItem = clear
        refresh()
    }

    private func refresh() {
        let count = stack.clips.count
        // The number beside the icon is how many are still waiting for ⌘V.
        let waiting = stack.remaining
        statusItem?.button?.title = count > 1 && waiting > 0 ? " \(waiting)" : ""
        pasteAllItem?.isEnabled = count > 0
        clearItem?.isEnabled = count > 0
    }

    @objc private func pasteAllFromMenu() {
        // The menu has to close and hand the keyboard back to the app underneath first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.pasteAll()
        }
    }

    @objc private func clearStack() {
        stack.clear()
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSSound.beep()
        }
        sender.state = service.status == .enabled ? .on : .off
    }

    @objc private func willTerminate() {
        paster.removeExportedFiles()
    }
}
