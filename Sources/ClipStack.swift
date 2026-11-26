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
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.poll()
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Call right after writing to the pasteboard ourselves, so our own writes are not mistaken for copies.
    func sync() {
        lastChange = pasteboard.changeCount
    }

    private func poll() {
        let change = pasteboard.changeCount
        guard change != lastChange else { return }
        lastChange = change
        // Asking which formats are present does not ask for the contents, so this never looks like a paste.
        if pasteboard.types?.contains(Offer.marker) == true { return }
        if let clip = Clip.capture(from: pasteboard) {
            onCopy?(clip)
        } else {
            onPrivateCopy?()
        }
    }
}
