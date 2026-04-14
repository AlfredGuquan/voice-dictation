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

    // Layout constants (v0.3 design: 232x40, radius 22)
    private let pillWidth: CGFloat = 232
    private let pillHeight: CGFloat = 40
    private let cornerRadius: CGFloat = 22
    private let buttonSize: CGFloat = 30
    private let buttonInset: CGFloat = 5
    private let barCount = 10
    private let waveformBaseHeights: [CGFloat] = [8, 14, 20, 26, 22, 24, 18, 20, 12, 16]
    private let progressStageOneDuration: CFTimeInterval = 0.5
    private let progressStageTwoDuration: CFTimeInterval = 2.5
    private let progressCompleteDuration: CFTimeInterval = 0.2

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
    private var progressPhase: ProgressPhase = .idle
    private var progressCurrent: CGFloat = 0  // last committed fill ratio [0,1]

    private enum ProgressPhase {
        case idle
        case stageOne
        case stageTwo
        case completing
    }

    // Colors — Warm Glass theme (v0.3: bg alpha 0.82 -> 0.92)
    private let bgColor = NSColor(red: 1.0, green: 0.99, blue: 0.98, alpha: 0.92)
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
        // Container with pill shape (radius 22, not full capsule)
        containerView = NSView(frame: view.bounds)
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = cornerRadius
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

        // Border (0.05 alpha per v0.3 brief)
        containerView.layer?.borderWidth = 1
        containerView.layer?.borderColor = NSColor(white: 0, alpha: 0.05).cgColor

        // Shadow on parent view — uses shadowPath to avoid rectangular halo (F6)
        view.wantsLayer = true
        if let rootLayer = view.layer {
            rootLayer.shadowColor = NSColor(red: 60/255, green: 40/255, blue: 25/255, alpha: 1).cgColor
            rootLayer.shadowOffset = CGSize(width: 0, height: -6)
            rootLayer.shadowRadius = 20
            rootLayer.shadowOpacity = 0.10
            rootLayer.shadowPath = CGPath(
                roundedRect: view.bounds,
                cornerWidth: cornerRadius,
                cornerHeight: cornerRadius,
                transform: nil
            )
        }

        // Cancel button (left)
        cancelButton = makeCircleButton(
            backgroundColor: cancelBgColor,
            symbolColor: cancelColor
        )
        cancelButton.frame.origin = CGPoint(x: buttonInset, y: (pillHeight - buttonSize) / 2)
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
            x: pillWidth - buttonSize - buttonInset,
            y: (pillHeight - buttonSize) / 2
        )
        drawCheckmark(on: confirmButton)
        confirmButton.target = self
        confirmButton.action = #selector(confirmTapped)
        containerView.addSubview(confirmButton)

        // Waveform container (center area)
        let centerGap: CGFloat = 6
        let centerX = buttonInset + buttonSize + centerGap
        let centerWidth = pillWidth - (buttonInset + buttonSize + centerGap) * 2
        waveformContainer = NSView(
            frame: NSRect(x: centerX, y: 0, width: centerWidth, height: pillHeight)
        )
        containerView.addSubview(waveformContainer)

        // Create waveform bars (v0.3: 10 bars, width 2.5, gap 2.5)
        let barWidth: CGFloat = 2.5
        let barGap: CGFloat = 2.5
        let totalBarsWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barGap
        let startX = (centerWidth - totalBarsWidth) / 2

        for i in 0..<barCount {
            let bar = NSView()
            bar.wantsLayer = true
            bar.layer?.backgroundColor = accentColor.withAlphaComponent(0.8).cgColor
            bar.layer?.cornerRadius = barWidth / 2

            let height = waveformBaseHeights[i % waveformBaseHeights.count]
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

        // Progress label (top half of pill)
        let labelHeight: CGFloat = 14
        progressLabel = NSTextField(
            frame: NSRect(x: 8, y: pillHeight / 2, width: centerWidth - 16, height: labelHeight)
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

        // Progress track (bottom half of pill, v0.3: height 2.5, bg 0.07)
        let trackHeight: CGFloat = 2.5
        let trackInset: CGFloat = 8
        let trackY = pillHeight / 2 - trackHeight - 4
        progressTrack = NSView(
            frame: NSRect(
                x: trackInset,
                y: trackY,
                width: centerWidth - trackInset * 2,
                height: trackHeight
            )
        )
        progressTrack.wantsLayer = true
        progressTrack.layer?.backgroundColor = NSColor(white: 0, alpha: 0.07).cgColor
        progressTrack.layer?.cornerRadius = trackHeight / 2
        progressContainer.addSubview(progressTrack)

        // Progress fill (width driven by CAAnimation — starts at 0)
        progressFill = NSView(
            frame: NSRect(x: 0, y: 0, width: 0, height: trackHeight)
        )
        progressFill.wantsLayer = true
        progressFill.layer?.cornerRadius = trackHeight / 2
        progressFill.layer?.backgroundColor = accentColor.cgColor
        progressFill.layer?.anchorPoint = CGPoint(x: 0, y: 0.5)
        progressTrack.addSubview(progressFill)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // Keep shadowPath in sync with any bounds change so rounded halo never drifts to rect.
        view.layer?.shadowPath = CGPath(
            roundedRect: view.bounds,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
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

        for (i, bar) in waveformBars.enumerated() {
            let baseHeight = waveformBaseHeights[i % waveformBaseHeights.count]
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
        for (i, bar) in waveformBars.enumerated() {
            let baseHeight = waveformBaseHeights[i % waveformBaseHeights.count]
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

    // MARK: - Progress animation (F11 trickle, state-driven)
    //
    // Three phases:
    //   1. 0   → 70%  over 500ms  (ease-out)
    //   2. 70% → 95%  over 2500ms (slower asymptote)
    //   3. 95% → 100% over 200ms  (linear) on ASR completion
    // Invariant: fill width never decreases. Re-entry via `startProgressAnimation()`
    // is a no-op if already running; a full reset requires explicit `resetProgress()`.

    private func startProgressAnimation() {
        resetProgress()
        progressPhase = .stageOne
        progressFill.alphaValue = 1

        animateFill(to: 0.70,
                    duration: progressStageOneDuration,
                    timing: CAMediaTimingFunction(controlPoints: 0.25, 0.9, 0.35, 1)
        ) { [weak self] finished in
            guard let self = self, finished, self.progressPhase == .stageOne else { return }
            self.progressPhase = .stageTwo
            self.animateFill(to: 0.95,
                             duration: self.progressStageTwoDuration,
                             timing: CAMediaTimingFunction(controlPoints: 0.3, 0.7, 0.4, 1),
                             completion: nil)
        }
    }

    /// External entry: ASR pipeline finished → jump to 100% then caller hides the pill.
    func completeProgressAnimation(completion: (() -> Void)? = nil) {
        guard progressPhase != .idle else {
            completion?()
            return
        }
        progressPhase = .completing
        animateFill(to: 1.0,
                    duration: progressCompleteDuration,
                    timing: CAMediaTimingFunction(name: .linear)
        ) { _ in
            completion?()
        }
    }

    private func stopProgressAnimation() {
        // Cancel any in-flight chained animation and reset fill to 0 without animation.
        progressPhase = .idle
        resetProgress()
    }

    private func resetProgress() {
        progressCurrent = 0
        progressFill.layer?.removeAllAnimations()
        progressFill.frame = NSRect(
            x: 0, y: 0,
            width: 0,
            height: progressTrack.bounds.height
        )
    }

    /// Animate fill ratio toward `target` (clamped, monotonic). Completion is called
    /// with `finished = true` only if the animation reached its target without being
    /// cancelled (phase changed or view torn down).
    private func animateFill(
        to target: CGFloat,
        duration: CFTimeInterval,
        timing: CAMediaTimingFunction,
        completion: ((Bool) -> Void)?
    ) {
        let trackWidth = progressTrack.bounds.width
        let clamped = min(1.0, max(progressCurrent, target))
        guard clamped > progressCurrent else {
            completion?(true)
            return
        }
        let targetWidth = trackWidth * clamped
        let startedPhase = progressPhase

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = timing
            progressFill.animator().frame = NSRect(
                x: 0, y: 0,
                width: targetWidth,
                height: progressTrack.bounds.height
            )
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            let cancelled = self.progressPhase != startedPhase
            if !cancelled {
                self.progressCurrent = clamped
            }
            completion?(!cancelled)
        })
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
