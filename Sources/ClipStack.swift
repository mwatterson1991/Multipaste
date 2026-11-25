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

    // Bounds memory for someone who copies all day and only ever pastes from a menu.
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
            clips.removeFirst(clips.count - limit)
        }
        onChange?()
        return true
    }

    /// The copy the next ⌘V should paste, oldest first.
    /// Nil when there is only one copy (the ordinary clipboard) or every copy has been pasted.
    func takeNext() -> Clip? {
        guard clips.count > 1, nextIndex < clips.count else { return nil }
        let clip = clips[nextIndex]
        nextIndex += 1
        onChange?()
        return clip
    }

    /// The stack stays until the next copy, so the same set can be pasted again somewhere else.
    func markPasted() {
        pasted = true
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

    private let pasteboard = NSPasteboard.general
    private var lastChange: Int
    private var timer: Timer?

    init() {
        lastChange = NSPasteboard.general.changeCount
    }

    // macOS has no "something was copied" notification; watching the change counter is how every clipboard tool does it.
    func start() {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.poll()
        }
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
        guard let clip = Clip.capture(from: pasteboard) else { return }
        onCopy?(clip)
    }
}
