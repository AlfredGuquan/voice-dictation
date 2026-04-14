// F6 tracer (production code): instantiate the real FloatingPillPanel + PillViewController
// Run: swift tracer/v03-gui/F6-pill-border/demo-prod.swift

import Cocoa

let src1 = "/Users/alfred.gu/Desktop/2-projects/voice-dictation/Sources/VoiceDictation/FloatingPillPanel.swift"
let src2 = "/Users/alfred.gu/Desktop/2-projects/voice-dictation/Sources/VoiceDictation/PillViewController.swift"
// Both have `final class`. We can't include them as sources directly via `swift run` — instead, this file
// expects to be compiled into the same unit. We accomplish this via `swift <file1> <file2> demo-prod.swift`.

// Build a minimal driver
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

guard let screen = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main else {
    fputs("no screen\n", stderr); exit(1)
}

// Force pill onto built-in display using production factory
// Production create() uses NSScreen.main; patch by monkey-placing via low-level create
guard let panel = FloatingPillPanel.create() else {
    fputs("cannot create panel\n", stderr); exit(1)
}

// If panel ended up on external screen, relocate to built-in
let f = screen.visibleFrame
var frame = panel.frame
frame.origin.x = f.midX - frame.width / 2
frame.origin.y = f.minY + 40
panel.setFrame(frame, display: false)

let vc = PillViewController()
panel.contentViewController = vc

panel.orderFrontRegardless()
vc.switchToRecording()

print("[F6-prod] pill shown — capturing 3 frames: recording / processing / after level update")

DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
    let t = Process()
    t.launchPath = "/usr/sbin/screencapture"
    t.arguments = ["-x", "-D", "1", "/tmp/f6-prod-recording.png"]
    try? t.run(); t.waitUntilExit()
    print("[F6-prod] captured recording")

    vc.updateAudioLevel(0.8)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        let t2 = Process()
        t2.launchPath = "/usr/sbin/screencapture"
        t2.arguments = ["-x", "-D", "1", "/tmp/f6-prod-with-level.png"]
        try? t2.run(); t2.waitUntilExit()
        print("[F6-prod] captured with-level")

        vc.switchToProcessing()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let t3 = Process()
            t3.launchPath = "/usr/sbin/screencapture"
            t3.arguments = ["-x", "-D", "1", "/tmp/f6-prod-processing.png"]
            try? t3.run(); t3.waitUntilExit()
            print("[F6-prod] captured processing — exit")
            NSApp.terminate(nil)
        }
    }
}

app.run()
