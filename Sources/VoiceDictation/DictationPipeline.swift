import Cocoa
import Foundation

/// Orchestrates the full dictation flow:
/// hotkey → record → ASR → cleanup → inject text
final class DictationPipeline {

    enum State {
        case idle
        case recording
        case processing
    }

    private(set) var state: State = .idle

    private let hotkeyManager = HotkeyManager()
    private let audioRecorder = AudioRecorder()
    private var whisperService: WhisperService?
    private var cleanupService: LLMCleanupService?

    // UI
    private var pillPanel: FloatingPillPanel?
    private var pillVC: PillViewController?
    private var levelUpdateTimer: Timer?

    // Current recording URL
    private var currentAudioURL: URL?

    func start() {
        // Load API key
        let env = EnvLoader.load()
        guard let apiKey = env["OPENAI_API_KEY"], !apiKey.isEmpty else {
            print("[Pipeline] ERROR: OPENAI_API_KEY not found in .env")
            showNotification("Voice Dictation Error", body: "OPENAI_API_KEY not found. Create .env file.")
            return
        }

        whisperService = WhisperService(apiKey: apiKey)
        cleanupService = LLMCleanupService(apiKey: apiKey)

        // Setup hotkey
        hotkeyManager.onEvent = { [weak self] event in
            guard let self = self else { return }
            switch event {
            case .toggleRecording:
                self.handleToggle()
            case .cancel:
                self.handleCancel()
            }
        }

        let success = hotkeyManager.start()
        if !success {
            showNotification(
                "Voice Dictation",
                body: "Accessibility permission required. Grant access in System Preferences."
            )
        }

        print("[Pipeline] Ready. Press Right Option to start/stop dictation.")
    }

    // MARK: - Event handlers

    private func handleToggle() {
        switch state {
        case .idle:
            startRecording()
        case .recording:
            stopAndProcess()
        case .processing:
            // Ignore toggle during processing
            break
        }
    }

    private func handleCancel() {
        guard state == .recording else { return }
        state = .idle
        hotkeyManager.isActive = false
        audioRecorder.cancelRecording()
        currentAudioURL = nil
        hidePill()
        stopLevelUpdates()
        print("[Pipeline] Recording cancelled")
    }

    // MARK: - Recording

    private func startRecording() {
        do {
            let url = try audioRecorder.startRecording()
            currentAudioURL = url
            state = .recording
            hotkeyManager.isActive = true
            showPill(state: .recording)
            startLevelUpdates()
            print("[Pipeline] Recording started")
        } catch {
            print("[Pipeline] Failed to start recording: \(error)")
            showNotification("Voice Dictation Error", body: "Failed to start recording: \(error.localizedDescription)")
        }
    }

    private func stopAndProcess() {
        guard state == .recording else { return }
        state = .processing
        hotkeyManager.isActive = false
        stopLevelUpdates()

        guard let audioURL = audioRecorder.stopRecording() else {
            state = .idle
            hidePill()
            return
        }

        currentAudioURL = audioURL
        updatePill(state: .processing)

        // Run ASR + cleanup pipeline
        Task {
            await processAudio(url: audioURL)
        }
    }

    // MARK: - Processing pipeline

    private func processAudio(url: URL) async {
        guard let whisper = whisperService, let cleanup = cleanupService else {
            await MainActor.run { handleError("Services not initialized", audioURL: url) }
            return
        }

        do {
            // Step 1: Transcribe
            print("[Pipeline] Transcribing...")
            let transcription = try await whisper.transcribe(fileURL: url)
            let rawText = transcription.text

            if rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await MainActor.run {
                    self.state = .idle
                    hidePill()
                    print("[Pipeline] Empty transcription, nothing to inject")
                }
                // Clean up temp file
                try? FileManager.default.removeItem(at: url)
                return
            }

            // Step 2: Cleanup
            print("[Pipeline] Cleaning up...")
            let cleanedText = try await cleanup.cleanup(rawText: rawText)

            if cleanedText.isEmpty {
                await MainActor.run {
                    self.state = .idle
                    hidePill()
                    print("[Pipeline] Cleaned text is empty, nothing to inject")
                }
                try? FileManager.default.removeItem(at: url)
                return
            }

            // Step 3: Inject text
            await MainActor.run {
                print("[Pipeline] Injecting: \(cleanedText)")
                TextInjector.inject(cleanedText)
                self.state = .idle
                hidePill()
            }

            // Clean up temp audio file
            try? FileManager.default.removeItem(at: url)

        } catch {
            await MainActor.run {
                handleError(error.localizedDescription, audioURL: url)
            }
        }
    }

    private func handleError(_ message: String, audioURL: URL) {
        print("[Pipeline] Error: \(message)")
        state = .idle
        hidePill()

        // Save audio to history for retry
        if let historyURL = audioRecorder.moveToHistory(audioURL) {
            showNotification(
                "Voice Dictation Error",
                body: "\(message)\nAudio saved: \(historyURL.lastPathComponent)"
            )
        } else {
            showNotification("Voice Dictation Error", body: message)
        }
    }

    // MARK: - Pill UI

    private func showPill(state: PillViewController.PillState) {
        let vc = PillViewController()
        vc.onCancel = { [weak self] in
            self?.handleCancel()
        }
        vc.onConfirm = { [weak self] in
            self?.stopAndProcess()
        }

        let panel = FloatingPillPanel.create()
        panel.contentView = vc.view
        panel.contentViewController = vc

        self.pillVC = vc
        self.pillPanel = panel

        vc.switchToRecording()
        panel.showAnimated()
    }

    private func updatePill(state: PillViewController.PillState) {
        switch state {
        case .recording:
            pillVC?.switchToRecording()
        case .processing:
            pillVC?.switchToProcessing()
        }
    }

    private func hidePill() {
        pillPanel?.hideAnimated { [weak self] in
            self?.pillPanel = nil
            self?.pillVC = nil
        }
    }

    // MARK: - Audio level updates for waveform

    private func startLevelUpdates() {
        levelUpdateTimer?.invalidate()
        levelUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) {
            [weak self] _ in
            guard let self = self, self.state == .recording else { return }
            let level = self.audioRecorder.currentLevel
            self.pillVC?.updateAudioLevel(level)
        }
    }

    private func stopLevelUpdates() {
        levelUpdateTimer?.invalidate()
        levelUpdateTimer = nil
    }

    // MARK: - Notifications

    private func showNotification(_ title: String, body: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = [
            "-e",
            "display notification \"\(body)\" with title \"\(title)\"",
        ]
        try? task.run()
    }
}
