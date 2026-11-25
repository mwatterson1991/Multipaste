import AppKit
import Carbon.HIToolbox

/// Sends the stack to whichever app is in front.
final class Paster {
    private let stack: ClipStack
    private let watcher: PasteboardWatcher
    private var busy = false

    /// True while Paste All is pressing ⌘V itself.
    var isBusy: Bool {
        busy
    }

    init(stack: ClipStack, watcher: PasteboardWatcher) {
        self.stack = stack
        self.watcher = watcher
    }

    func pasteAll() {
        guard !busy, !stack.clips.isEmpty else { return }
        busy = true
        let clips = stack.clips
        afterModifiersLift(until: Date().addingTimeInterval(1)) { [self] in
            if !pasteTogether(clips) {
                pasteInTurn(clips, from: 0)
            }
        }
    }

    func removeExportedFiles() {
        try? FileManager.default.removeItem(at: exportRoot)
    }

    // The shortcut's own ⌃ and ⌘ are still down when it fires. Pasting before they lift could send ⌃⌘V instead of ⌘V.
    private func afterModifiersLift(until deadline: Date, _ body: @escaping () -> Void) {
        let held = NSEvent.modifierFlags.intersection([.command, .control, .option, .shift])
        if held.isEmpty || Date() >= deadline {
            body()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [self] in
            afterModifiersLift(until: deadline, body)
        }
    }

    /// One ⌘V for the whole stack, so a canvas lays images out side by side and a single undo removes them.
    /// False when the stack can't travel as one paste.
    private func pasteTogether(_ clips: [Clip]) -> Bool {
        guard clips.count > 1 else { return false }
        let pasteboard = NSPasteboard.general

        if clips.allSatisfy({ $0.kind == .text }) {
            let lines = clips.compactMap { $0.text }
            pasteboard.clearContents()
            _ = pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
        } else if clips.allSatisfy({ $0.kind == .image || $0.kind == .files }) {
            guard let urls = exportFiles(for: clips), !urls.isEmpty else { return false }
            pasteboard.clearContents()
            _ = pasteboard.writeObjects(urls.map { $0 as NSURL })
        } else {
            return false
        }

        watcher.sync()
        let ours = pasteboard.changeCount
        pressPaste()
        stack.markAllPasted()

        // ⌘V should still mean "the last thing I copied", so that goes back once the app has taken the group.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
            if pasteboard.changeCount == ours, let last = clips.last {
                last.write(to: pasteboard)
                watcher.sync()
            }
            busy = false
        }
        return true
    }

    /// For a stack that mixes kinds (say text and images): each copy pasted on its own, exactly as it was copied.
    private func pasteInTurn(_ clips: [Clip], from index: Int) {
        guard index < clips.count else {
            stack.markAllPasted()
            busy = false
            return
        }
        clips[index].write(to: NSPasteboard.general)
        watcher.sync()
        pressPaste()
        // The app reads the pasteboard a moment after the keystroke; the next copy has to wait for that.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            pasteInTurn(clips, from: index + 1)
        }
    }

    private func pressPaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    private var exportRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(AppInfo.name, isDirectory: true)
    }

    /// Images become numbered files so the receiving app keeps them in the order they were copied.
    private func exportFiles(for clips: [Clip]) -> [URL]? {
        let fileManager = FileManager.default

        // Each paste gets its own folder so a second paste can't overwrite files an app is still reading.
        // Folders older than ten minutes have long since been read.
        if let earlier = try? fileManager.contentsOfDirectory(at: exportRoot, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for folder in earlier {
                let values = try? folder.resourceValues(forKeys: [.contentModificationDateKey])
                if let modified = values?.contentModificationDate, modified.timeIntervalSinceNow < -600 {
                    try? fileManager.removeItem(at: folder)
                }
            }
        }

        let folder = exportRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        var urls: [URL] = []
        var number = 0
        for clip in clips {
            if clip.kind == .files {
                urls.append(contentsOf: clip.fileURLs)
                continue
            }
            guard let file = clip.imageFile else { return nil }
            number += 1
            let name = (number < 10 ? "0\(number)" : "\(number)") + "." + file.fileExtension
            let url = folder.appendingPathComponent(name)
            do {
                try file.data.write(to: url)
            } catch {
                return nil
            }
            urls.append(url)
        }
        return urls
    }
}
