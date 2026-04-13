import Cocoa

/// Custom NSPanel that never becomes key window — ensures it doesn't steal focus
/// from the user's active text field.
final class FloatingPillPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Create a pill-shaped floating panel positioned at screen bottom center.
    static func create(width: CGFloat = 280, height: CGFloat = 48) -> FloatingPillPanel {
        guard let screen = NSScreen.main else {
            fatalError("No main screen available")
        }

        let screenFrame = screen.visibleFrame
        let panelX = screenFrame.midX - width / 2
        let panelY = screenFrame.minY + 40  // 40pt above bottom edge

        let panel = FloatingPillPanel(
            contentRect: NSRect(x: panelX, y: panelY, width: width, height: height),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow

        return panel
    }

    /// Show the panel with a slide-up animation from below.
    func showAnimated() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let targetY = screenFrame.minY + 40

        // Start below screen
        var frame = self.frame
        frame.origin.y = screenFrame.minY - frame.height
        self.setFrame(frame, display: false)
        self.alphaValue = 0

        self.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            var targetFrame = self.frame
            targetFrame.origin.y = targetY
            self.animator().setFrame(targetFrame, display: true)
            self.animator().alphaValue = 1
        })
    }

    /// Hide the panel with a slide-down animation.
    func hideAnimated(completion: (() -> Void)? = nil) {
        guard let screen = NSScreen.main else {
            self.orderOut(nil)
            completion?()
            return
        }
        let screenFrame = screen.visibleFrame

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            var targetFrame = self.frame
            targetFrame.origin.y = screenFrame.minY - self.frame.height
            self.animator().setFrame(targetFrame, display: true)
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            completion?()
        })
    }
}
