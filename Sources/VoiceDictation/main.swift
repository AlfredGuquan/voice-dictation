import Cocoa

#if DEBUG
// Line-buffer stdout so headless QA can `tail -f` the log without waiting
// for a 4 KB block to flush. No-op for release builds.
setlinebuf(stdout)
#endif

// Set activation policy to accessory (no Dock icon, no app switcher entry)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate

app.run()
