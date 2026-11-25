import AppKit

// A menu bar app with no Dock icon and no windows of its own.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)

let controller = Controller()
controller.start()

application.run()
