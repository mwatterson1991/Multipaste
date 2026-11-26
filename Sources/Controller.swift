import AppKit
import Carbon.HIToolbox
import ServiceManagement

/// Wires the pieces together and owns the menu bar item.
final class Controller: NSObject {
    private let stack = ClipStack()
    private let watcher = PasteboardWatcher()
    private let allAtOnce = AllAtOnce()
    private let cursorCount = CursorCount()
    private let pasteboard = NSPasteboard.general

    /// The copy currently on the clipboard as a promise.
    private var offer: Offer?
    /// True from the first time a paste asks for the copy on offer until that paste is counted.
    private var pasteSeen = false
    private var settle: DispatchWorkItem?
    // One paste asks for its formats in quick succession. The next copy goes on the clipboard once the asking stops,
    // so a paste can't end up with half of one copy and half of the next.
    private static let quiet: TimeInterval = 0.2

    private var hotKey: HotKey?
    private var statusItem: NSStatusItem?
    private var pasteAllItem: NSMenuItem?
    private var clearItem: NSMenuItem?
    private var signals: [DispatchSourceSignal] = []
    private var awake: NSObjectProtocol?

    func start() {
        // macOS slows the timers of an app with nothing on screen. A slow check here would leave a longer gap
        // in which a paste goes unseen. The Mac can still go to sleep.
        awake = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Watching the clipboard")

        buildMenu()

        stack.onChange = { [weak self] in
            self?.refresh()
        }
        watcher.onCopy = { [weak self] clip in
            self?.copied(clip)
        }
        watcher.onPrivateCopy = { [weak self] in
            self?.leaveClipboardAlone()
        }
        watcher.start()

        // ⌘V pastes the next copy. ⌃⌘V makes the next ⌘V paste all of them: next to ⌘V under the same hand, and unused by macOS and Figma.
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | controlKey)) { [weak self] in
            self?.loadAll()
        }

        // Quitting any other way than the menu should still hand the clipboard back in working order.
        on(SIGTERM) {
            NSApp.terminate(nil)
        }
        // The automatic build can't press ⌃⌘V, so it uses this to check Paste All.
        if Log.enabled {
            on(SIGUSR1) { [weak self] in
                self?.loadAll()
            }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(willTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
        Log.note("started")
    }

    private func on(_ signalNumber: Int32, _ body: @escaping () -> Void) {
        _ = signal(signalNumber, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
        source.setEventHandler(handler: body)
        source.resume()
        signals.append(source)
    }

    // MARK: Copying

    private func copied(_ clip: Clip) {
        // A paste still being read is over as far as this copy is concerned: it starts a new stack.
        if pasteSeen {
            countPaste()
        }
        if stack.add(clip) {
            // One copy is the ordinary clipboard; the number only has something to say from the second.
            let count = stack.clips.count
            Log.note("copied stack=\(count)")
            if count > 1 {
                cursorCount.show(count)
            }
        }
        // The source app has just put its own copy on the clipboard. The oldest unpasted one goes back in its place.
        offerNext()
    }

    /// A password manager's copy, or an emptied clipboard. Nothing is kept and nothing is put in its way.
    private func leaveClipboardAlone() {
        settle?.cancel()
        settle = nil
        pasteSeen = false
        offer = nil
        stack.clear()
        Log.note("left alone")
    }

    // MARK: Pasting

    private func offerNext() {
        guard let clip = stack.next else { return }
        let next = Offer(clip: clip)
        next.onTaken = { [weak self, weak next] in
            guard let self = self, let next = next else { return }
            self.taken(from: next)
        }
        offer = next
        next.write(to: pasteboard)
        watcher.sync()
    }

    /// Runs when something asks the clipboard for the copy on offer, which is what a paste does.
    private func taken(from source: Offer) {
        // An earlier promise can still be asked while the clipboard lets go of it. After the last copy
        // has been pasted there is nothing to move on to, and ⌘V keeps giving that one.
        guard source === offer, stack.next != nil else { return }
        pasteSeen = true
        settle?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pasteSettled()
        }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Controller.quiet, execute: work)
    }

    private func countPaste() {
        settle?.cancel()
        settle = nil
        pasteSeen = false
        // The next copy after any paste starts a new stack.
        stack.advance()
    }

    private func pasteSettled() {
        guard pasteSeen else { return }
        countPaste()
        Log.note("pasted left=\(stack.remaining)")
        offerNext()
    }

    /// Paste All. The app can't press ⌘V for you without the Accessibility permission, so it loads the clipboard and the next ⌘V does the rest.
    private func loadAll() {
        let clips = stack.clips
        guard allAtOnce.load(clips, onto: pasteboard) else {
            NSSound.beep()
            return
        }
        watcher.sync()
        settle?.cancel()
        settle = nil
        pasteSeen = false
        offer = nil
        stack.markAllPasted()
        cursorCount.show(clips.count)
        Log.note("loaded all=\(clips.count)")
    }

    // MARK: Menu bar

    private func buildMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "square.stack", accessibilityDescription: AppInfo.name)
        item.button?.imagePosition = .imageLeading

        let pasteAll = NSMenuItem(title: "Paste All with Next ⌘V", action: #selector(loadAllFromMenu), keyEquivalent: "v")
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
        // Paste All and Clear are switched off by hand when there is nothing for them to do.
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
        pasteAllItem?.isEnabled = count > 1
        clearItem?.isEnabled = count > 0
    }

    @objc private func loadAllFromMenu() {
        loadAll()
    }

    /// Back to the ordinary clipboard: the stack is forgotten and ⌘V gives the last thing copied.
    @objc private func clearStack() {
        let last = stack.clips.last
        let ours = watcher.isUnchanged
        settle?.cancel()
        settle = nil
        pasteSeen = false
        offer = nil
        stack.clear()
        if ours, let last = last {
            last.write(to: pasteboard)
            watcher.sync()
        }
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
        // A promise can't be kept once the app is gone, so the clipboard gets the last copy in full.
        if watcher.isUnchanged, let last = stack.clips.last {
            last.write(to: pasteboard)
        }
        allAtOnce.removeExportedFiles()
    }
}
