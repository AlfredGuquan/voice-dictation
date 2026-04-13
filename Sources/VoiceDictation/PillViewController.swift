import Cocoa

/// Manages the floating pill UI content: recording waveform, processing progress bar.
final class PillViewController: NSViewController {

    enum PillState {
        case recording
        case processing
    }

    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?

    private(set) var state: PillState = .recording

    // Layout constants
    private let pillWidth: CGFloat = 280
    private let pillHeight: CGFloat = 48
    private let buttonSize: CGFloat = 36
    private let barCount = 12

    // Views
    private var containerView: NSView!
    private var visualEffectView: NSVisualEffectView!
    private var cancelButton: NSButton!
    private var confirmButton: NSButton!
    private var waveformBars: [NSView] = []
    private var waveformContainer: NSView!
    private var progressContainer: NSView!
    private var progressTrack: NSView!
    private var progressFill: NSView!
    private var progressLabel: NSTextField!

    // Animation
    private var waveformTimer: Timer?
    private var progressTimer: Timer?
    private var progressValue: CGFloat = 0

    // Colors — Warm Glass theme from mockup
    private let bgColor = NSColor(red: 1.0, green: 0.99, blue: 0.98, alpha: 0.82)
    private let accentColor = NSColor(red: 217/255, green: 119/255, blue: 87/255, alpha: 1.0)  // #D97757
    private let accentHoverColor = NSColor(red: 196/255, green: 101/255, blue: 58/255, alpha: 1.0)  // #C4653A
    private let confirmColor = NSColor(red: 93/255, green: 140/255, blue: 90/255, alpha: 1.0)  // #5D8C5A
    private let confirmBgColor = NSColor(red: 93/255, green: 140/255, blue: 90/255, alpha: 0.10)
    private let cancelColor = NSColor(red: 196/255, green: 101/255, blue: 58/255, alpha: 1.0)  // #C4653A
    private let cancelBgColor = NSColor(red: 196/255, green: 101/255, blue: 58/255, alpha: 0.08)
    private let textSecondary = NSColor(red: 107/255, green: 101/255, blue: 96/255, alpha: 1.0)  // #6B6560

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: pillWidth, height: pillHeight))
        setupUI()
    }

    private func setupUI() {
        // Container with pill shape
        containerView = NSView(frame: view.bounds)
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = pillHeight / 2
        containerView.layer?.masksToBounds = true
        view.addSubview(containerView)

        // Visual effect (frosted glass)
        visualEffectView = NSVisualEffectView(frame: containerView.bounds)
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        containerView.addSubview(visualEffectView)

        // Semi-transparent warm overlay
        let warmOverlay = NSView(frame: containerView.bounds)
        warmOverlay.wantsLayer = true
        warmOverlay.layer?.backgroundColor = bgColor.cgColor
        containerView.addSubview(warmOverlay)

        // Border
        containerView.layer?.borderWidth = 1
        containerView.layer?.borderColor = NSColor(white: 0, alpha: 0.06).cgColor

        // Shadow on parent view
        view.wantsLayer = true
        view.shadow = NSShadow()
        view.layer?.shadowColor = NSColor(white: 0, alpha: 0.15).cgColor
        view.layer?.shadowOffset = CGSize(width: 0, height: -4)
        view.layer?.shadowRadius = 24
        view.layer?.shadowOpacity = 1

        // Cancel button (left)
        cancelButton = makeCircleButton(
            backgroundColor: cancelBgColor,
            symbolColor: cancelColor
        )
        cancelButton.frame.origin = CGPoint(x: 6, y: (pillHeight - buttonSize) / 2)
        drawX(on: cancelButton)
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)
        containerView.addSubview(cancelButton)

        // Confirm button (right)
        confirmButton = makeCircleButton(
            backgroundColor: confirmBgColor,
            symbolColor: confirmColor
        )
        confirmButton.frame.origin = CGPoint(
            x: pillWidth - buttonSize - 6,
            y: (pillHeight - buttonSize) / 2
        )
        drawCheckmark(on: confirmButton)
        confirmButton.target = self
        confirmButton.action = #selector(confirmTapped)
        containerView.addSubview(confirmButton)

        // Waveform container (center area)
        let centerX = 6 + buttonSize + 8
        let centerWidth = pillWidth - (6 + buttonSize + 8) * 2
        waveformContainer = NSView(
            frame: NSRect(x: centerX, y: 0, width: centerWidth, height: pillHeight)
        )
        containerView.addSubview(waveformContainer)

        // Create waveform bars
        let barWidth: CGFloat = 3
        let barGap: CGFloat = 3
        let totalBarsWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barGap
        let startX = (centerWidth - totalBarsWidth) / 2

        let baseHeights: [CGFloat] = [8, 14, 20, 28, 22, 32, 18, 26, 14, 20, 10, 16]

        for i in 0..<barCount {
            let bar = NSView()
            bar.wantsLayer = true
            bar.layer?.backgroundColor = accentColor.withAlphaComponent(0.8).cgColor
            bar.layer?.cornerRadius = 1.5

            let height = baseHeights[i % baseHeights.count]
            let x = startX + CGFloat(i) * (barWidth + barGap)
            let y = (pillHeight - height) / 2
            bar.frame = NSRect(x: x, y: y, width: barWidth, height: height)

            waveformContainer.addSubview(bar)
            waveformBars.append(bar)
        }

        // Progress container (hidden initially)
        progressContainer = NSView(
            frame: NSRect(x: centerX, y: 0, width: centerWidth, height: pillHeight)
        )
        progressContainer.isHidden = true
        containerView.addSubview(progressContainer)

        // Progress label
        progressLabel = NSTextField(
            frame: NSRect(x: 16, y: pillHeight / 2 + 1, width: centerWidth - 32, height: 16)
        )
        progressLabel.stringValue = "Processing..."
        progressLabel.isEditable = false
        progressLabel.isBordered = false
        progressLabel.isSelectable = false
        progressLabel.backgroundColor = .clear
        progressLabel.textColor = textSecondary
        progressLabel.font = NSFont.systemFont(ofSize: 10)
        progressLabel.alignment = .center
        progressContainer.addSubview(progressLabel)

        // Progress track
        let trackHeight: CGFloat = 3
        let trackY = pillHeight / 2 - trackHeight - 3
        progressTrack = NSView(
            frame: NSRect(x: 16, y: trackY, width: centerWidth - 32, height: trackHeight)
        )
        progressTrack.wantsLayer = true
        progressTrack.layer?.backgroundColor = NSColor(white: 0, alpha: 0.06).cgColor
        progressTrack.layer?.cornerRadius = 1.5
        progressContainer.addSubview(progressTrack)

        // Progress fill
        progressFill = NSView(
            frame: NSRect(x: 0, y: 0, width: 0, height: trackHeight)
        )
        progressFill.wantsLayer = true
        progressFill.layer?.cornerRadius = 1.5
        // Gradient-like appearance using the accent color
        progressFill.layer?.backgroundColor = accentColor.cgColor
        progressTrack.addSubview(progressFill)
    }

    // MARK: - State transitions

    func switchToRecording() {
        state = .recording
        waveformContainer.isHidden = false
        progressContainer.isHidden = true
        confirmButton.isHidden = false
        startWaveformAnimation()
        stopProgressAnimation()
    }

    func switchToProcessing() {
        state = .processing
        waveformContainer.isHidden = true
        progressContainer.isHidden = false
        // Replace confirm button with spinner appearance
        confirmButton.isEnabled = false
        confirmButton.alphaValue = 0.5
        stopWaveformAnimation()
        startProgressAnimation()
    }

    // MARK: - Audio level

    /// Update waveform bars based on audio level (0.0 to 1.0)
    func updateAudioLevel(_ level: Float) {
        guard state == .recording else { return }
        let baseHeights: [CGFloat] = [8, 14, 20, 28, 22, 32, 18, 26, 14, 20, 10, 16]

        for (i, bar) in waveformBars.enumerated() {
            let baseHeight = baseHeights[i % baseHeights.count]
            // Scale bars by audio level with some randomness
            let scale = 0.3 + CGFloat(level) * 0.7 * (0.8 + CGFloat.random(in: 0...0.4))
            let newHeight = max(4, baseHeight * scale)
            let y = (pillHeight - newHeight) / 2

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.08
                bar.animator().frame = NSRect(
                    x: bar.frame.origin.x,
                    y: y,
                    width: bar.frame.width,
                    height: newHeight
                )
            }
        }
    }

    // MARK: - Waveform animation

    private func startWaveformAnimation() {
        waveformTimer?.invalidate()
        waveformTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) {
            [weak self] _ in
            self?.animateWaveformStep()
        }
    }

    private func animateWaveformStep() {
        let baseHeights: [CGFloat] = [8, 14, 20, 28, 22, 32, 18, 26, 14, 20, 10, 16]
        for (i, bar) in waveformBars.enumerated() {
            let baseHeight = baseHeights[i % baseHeights.count]
            // Idle animation: gentle bounce between 40% and 100% of base height
            let scale = 0.4 + 0.6 * CGFloat.random(in: 0...1)
            let newHeight = baseHeight * scale
            let y = (pillHeight - newHeight) / 2

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                bar.animator().frame = NSRect(
                    x: bar.frame.origin.x,
                    y: y,
                    width: bar.frame.width,
                    height: newHeight
                )
            }
        }
    }

    private func stopWaveformAnimation() {
        waveformTimer?.invalidate()
        waveformTimer = nil
    }

    // MARK: - Progress animation

    private func startProgressAnimation() {
        progressValue = 0
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) {
            [weak self] _ in
            self?.animateProgressStep()
        }
    }

    private func animateProgressStep() {
        progressValue += 0.01
        if progressValue > 1.0 { progressValue = 0 }

        let trackWidth = progressTrack.bounds.width
        // Sweep animation: fill grows then resets
        let fillWidth: CGFloat
        if progressValue < 0.7 {
            fillWidth = trackWidth * (progressValue / 0.7)
        } else {
            fillWidth = trackWidth * (1.0 - (progressValue - 0.7) / 0.3)
        }

        let opacity: CGFloat = progressValue < 0.5 ? 0.6 + progressValue * 0.8 : 1.4 - progressValue * 0.8

        progressFill.frame = NSRect(
            x: 0, y: 0,
            width: max(0, fillWidth),
            height: progressTrack.bounds.height
        )
        progressFill.alphaValue = opacity
    }

    private func stopProgressAnimation() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        onCancel?()
    }

    @objc private func confirmTapped() {
        onConfirm?()
    }

    // MARK: - Button helpers

    private func makeCircleButton(
        backgroundColor: NSColor,
        symbolColor: NSColor
    ) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: buttonSize, height: buttonSize))
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = buttonSize / 2
        button.layer?.backgroundColor = backgroundColor.cgColor
        button.title = ""
        return button
    }

    private func drawX(on button: NSButton) {
        let size = buttonSize
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) {
            [weak self] rect in
            guard let self = self else { return false }
            let path = NSBezierPath()
            path.lineWidth = 1.8
            path.lineCapStyle = .round
            self.cancelColor.setStroke()
            let inset: CGFloat = 12
            path.move(to: NSPoint(x: inset, y: inset))
            path.line(to: NSPoint(x: size - inset, y: size - inset))
            path.move(to: NSPoint(x: size - inset, y: inset))
            path.line(to: NSPoint(x: inset, y: size - inset))
            path.stroke()
            return true
        }
        button.image = image
    }

    private func drawCheckmark(on button: NSButton) {
        let size = buttonSize
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) {
            [weak self] rect in
            guard let self = self else { return false }
            let path = NSBezierPath()
            path.lineWidth = 2.0
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            self.confirmColor.setStroke()
            // Checkmark path matching mockup: polyline 3.5,8.5 6.5,11.5 12.5,4.5
            // Scale from 16x16 to button size
            let scale = size / 16
            path.move(to: NSPoint(x: 3.5 * scale, y: size - 8.5 * scale))
            path.line(to: NSPoint(x: 6.5 * scale, y: size - 11.5 * scale))
            path.line(to: NSPoint(x: 12.5 * scale, y: size - 4.5 * scale))
            path.stroke()
            return true
        }
        button.image = image
    }

    deinit {
        stopWaveformAnimation()
        stopProgressAnimation()
    }
}
