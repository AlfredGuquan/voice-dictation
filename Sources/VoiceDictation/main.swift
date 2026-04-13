import Cocoa

// Set activation policy to accessory (no Dock icon, no app switcher entry)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate

app.run()
