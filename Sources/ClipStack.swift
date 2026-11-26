import AppKit

/// Everything copied since the last paste.
final class ClipStack {
    private(set) var clips: [Clip] = []
    var onChange: (() -> Void)?

    private var pasted = false
    private var nextIndex = 0

    /// How many copies ⌘V has not handed over yet.
    var remaining: Int {
        max(0, clips.count - nextIndex)
    }

    // Bounds memory through a long run of copies with no paste.
    private let limit = 50

    /// False when the copy repeats the one before it, which is what pressing ⌘C twice out of habit does.
    @discardableResult
    func add(_ clip: Clip) -> Bool {
        if pasted {
            clips.removeAll()
            nextIndex = 0
            pasted = false
        }
        if clips.last == clip { return false }
        clips.append(clip)
        if clips.count > limit {
            let extra = clips.count - limit
            clips.removeFirst(extra)
            nextIndex = max(0, nextIndex - extra)
        }
        onChange?()
        return true
    }

    /// The copy the next ⌘V should paste, oldest first. Nil once every copy has been pasted.
    var next: Clip? {
        nextIndex < clips.count ? clips[nextIndex] : nil
    }

    /// Call when the copy on offer has been pasted.
    /// The stack stays until the next copy, so the whole set can still be pasted at once somewhere else.
    func advance() {
        pasted = true
        if nextIndex < clips.count {
            nextIndex += 1
        }
        onChange?()
    }

    func markAllPasted() {
        nextIndex = clips.count
        pasted = true
        onChange?()
    }

    func clear() {
        clips.removeAll()
        nextIndex = 0
        pasted = false
        onChange?()
    }
}

/// Notices when another app copies something.
final class PasteboardWatcher {
    var onCopy: ((Clip) -> Void)?
    /// Something is on the clipboard that must not be kept: a password manager's copy, or nothing at all.
    var onPrivateCopy: (() -> Void)?

    private let pasteboard = NSPasteboard.general
    private var lastChange: Int
    private var timer: Timer?
    /// A change has been seen and not read yet.
    private var unread = false
    private var emptyReads = 0

    private static let tick: TimeInterval = 0.025
    // Half a second of an empty clipboard means it was emptied, not that a copy is still on its way.
    private static let emptyReadsAllowed = 20

    init() {
        lastChange = NSPasteboard.general.changeCount
    }

    /// True while nothing else has written to the clipboard since this app last looked at it or wrote to it.
    var isUnchanged: Bool {
        pasteboard.changeCount == lastChange
    }

    // macOS has no "something was copied" notification; watching the change counter is how every clipboard tool does it.
    // The check is frequent because a paste made before the app has taken a new copy in goes unseen.
    func start() {
        let timer = Timer(timeInterval: PasteboardWatcher.tick, repeats: true) { [weak self] _ in
            self?.poll()
        }
        timer.tolerance = PasteboardWatcher.tick / 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Call right after writing to the pasteboard ourselves, so our own writes are not mistaken for copies.
    func sync() {
        lastChange = pasteboard.changeCount
        unread = false
    }

    private func poll() {
        let change = pasteboard.changeCount
        if change != lastChange {
            // An app can announce a copy a moment before it supplies the contents.
            // Reading on the next tick, not this one, gives it time to finish.
            lastChange = change
            unread = true
            emptyReads = 0
            return
        }
        guard unread else { return }

        // Asking which formats are present does not ask for the contents, so this never looks like a paste.
        if pasteboard.types?.contains(Offer.marker) == true {
            unread = false
            return
        }
        switch Clip.capture(from: pasteboard) {
        case .clip(let clip):
            unread = false
            onCopy?(clip)
        case .secret:
            unread = false
            onPrivateCopy?()
        case .nothing:
            emptyReads += 1
            if emptyReads >= PasteboardWatcher.emptyReadsAllowed {
                unread = false
                onPrivateCopy?()
            }
        }
    }
}
