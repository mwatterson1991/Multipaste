import AppKit

/// Puts the whole stack on the clipboard as a single paste.
final class AllAtOnce {
    /// One ⌘V for the whole stack, so a canvas lays images out side by side and a single undo removes them.
    /// False when the stack can't travel as one paste, which is the case when it mixes kinds (say text and images).
    func load(_ clips: [Clip], onto pasteboard: NSPasteboard) -> Bool {
        guard clips.count > 1 else { return false }

        if clips.allSatisfy({ $0.kind == .text }) {
            let lines = clips.compactMap { $0.text }
            pasteboard.clearContents()
            _ = pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
            return true
        }
        if clips.allSatisfy({ $0.kind == .image || $0.kind == .files }) {
            guard let urls = exportFiles(for: clips), !urls.isEmpty else { return false }
            pasteboard.clearContents()
            _ = pasteboard.writeObjects(urls.map { $0 as NSURL })
            return true
        }
        return false
    }

    func removeExportedFiles() {
        try? FileManager.default.removeItem(at: exportRoot)
    }

    private var exportRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(AppInfo.name, isDirectory: true)
    }

    /// Images become numbered files so the receiving app keeps them in the order they were copied.
    private func exportFiles(for clips: [Clip]) -> [URL]? {
        let fileManager = FileManager.default

        // Each load gets its own folder so a second one can't overwrite files an app is still reading.
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
