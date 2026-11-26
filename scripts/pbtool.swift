import AppKit

// A stand-in for other apps in the automatic build's checks. It copies and pastes the way they do.
// Not part of the app.

let arguments = Array(CommandLine.arguments.dropFirst())
let pasteboard = NSPasteboard.general

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func argument(_ position: Int) -> String {
    guard arguments.count > position else { fail("missing argument") }
    return arguments[position]
}

switch arguments.first ?? "" {
case "make-png":
    // Different sizes give different files.
    guard let side = Int(argument(1)),
          let bitmap = NSBitmapImageRep(
              bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
              hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let data = bitmap.representation(using: .png, properties: [:]) else { fail("could not make the image") }
    do {
        try data.write(to: URL(fileURLWithPath: argument(2)))
    } catch {
        fail("could not save the image")
    }

case "copy-png":
    guard let data = FileManager.default.contents(atPath: argument(1)) else { fail("no such file") }
    pasteboard.clearContents()
    _ = pasteboard.setData(data, forType: .png)

case "paste-png":
    guard let data = pasteboard.data(forType: .png) else { fail("no image on the clipboard") }
    FileHandle.standardOutput.write(data)

case "copy-rich":
    // Text in three formats at once, the way a browser or an editor copies it.
    let text = argument(1)
    let item = NSPasteboardItem()
    _ = item.setString(text, forType: .string)
    _ = item.setString("<b>\(text)</b>", forType: .html)
    _ = item.setData(Data("{\\rtf1 \(text)}".utf8), forType: .rtf)
    pasteboard.clearContents()
    _ = pasteboard.writeObjects([item])

case "paste-rich":
    // One paste that asks for two formats a moment apart. It must count as a single paste.
    let html = pasteboard.string(forType: .html) ?? "-"
    usleep(60_000)
    let text = pasteboard.string(forType: .string) ?? "-"
    print("\(text)|\(html)")

case "copy-private":
    // The way a password manager copies: with the marker that asks clipboard tools to keep out.
    let item = NSPasteboardItem()
    _ = item.setString(argument(1), forType: .string)
    _ = item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
    pasteboard.clearContents()
    _ = pasteboard.writeObjects([item])

case "paste-files":
    let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    for url in urls {
        print(url.path)
    }

case "formats":
    // Looks at which formats are on the clipboard without asking for any contents.
    print((pasteboard.types ?? []).map { $0.rawValue }.joined(separator: " "))

default:
    fail("unknown command")
}
