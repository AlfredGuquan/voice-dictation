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

    /// Where the cleaned text from a retry should land.
    /// `inject` is for the toast path (focus likely still on the origin app);
    /// `clipboard` is for the history-list path (user is in the main window).
    enum RetryOutput {
        case inject
        case clipboard
    }

    private(set) var state: State = .idle

    let hotkeyManager = HotkeyManager(hotkey: Config.hotkey)
    private let audioRecorder = AudioRecorder()
    let vocabularyStore = VocabularyStore()
    let historyStore = HistoryStore()
    private let whisperService = WhisperService()
    private let cleanupService = LLMCleanupService()

    // UI
    private var pillPanel: FloatingPillPanel?
    private var pillVC: PillViewController?
    private var levelUpdateTimer: Timer?

    // Current recording URL and start time (for duration)
    private var currentAudioURL: URL?
    private var recordingStartTime: Date?

    func start() {
        // Startup sanity check: warn the user if no key is configured yet.
        // Services read Config.apiKey on every request, so Settings updates
        // take effect without a restart.
        if Config.apiKey == nil {
            print("[Pipeline] WARNING: OPENAI_API_KEY not set; configure it in Settings")
            showNotification(
                "Voice Dictation",
                body: "OPENAI_API_KEY not set. Open Settings to configure."
            )
        }

        // Load personal vocabulary (creates default file if needed)
        vocabularyStore.load()

        // Load history
        historyStore.load()

        // Setup hotkey — dispatch per event kind (see HotkeyManager.HotkeyEvent)
        hotkeyManager.onEvent = { [weak self] event in
            guard let self = self else { return }
            switch event {
            case .singleModifierDown:
                // "Hold to talk" — start on press
                if self.state == .idle { self.startRecording() }
            case .singleModifierUp:
                // "Hold to talk" — stop on release
                if self.state == .recording { self.stopAndProcess() }
            case .comboPress:
                // "Press to toggle"
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

        // Hot reload: Settings posts .hotkeyConfigChanged after writing new hotkey.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeyConfigDidChange),
            name: .hotkeyConfigChanged,
            object: nil
        )
        // Capture bridge: while Settings is recording a new hotkey, tell the
        // global CGEvent tap to pass events through so the local NSEvent
        // monitor in SettingsView can receive them.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeyCaptureBegin),
            name: .hotkeyCaptureBegin,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeyCaptureEnd),
            name: .hotkeyCaptureEnd,
            object: nil
        )

        print("[Pipeline] Ready. Press \(hotkeyManager.currentHotkey.displayName) to dictate.")
    }

    @objc private func hotkeyConfigDidChange() {
        // Called on main thread via NotificationCenter from SettingsView save.
        // If recording is in flight, cancel it first — the user's old binding
        // is about to disappear and their "held" state would never receive a
        // matching release event.
        if state == .recording {
            handleCancel()
        }
        hotkeyManager.reload(to: Config.hotkey)
    }

    @objc private func hotkeyCaptureBegin() {
        // If the user starts recording a new hotkey mid-dictation, cancel
        // the in-flight recording so we don't strand `hotkeyManager.isActive`
        // and leak UI state.
        if state == .recording {
            handleCancel()
        }
        hotkeyManager.beginCapture()
    }

    @objc private func hotkeyCaptureEnd() {
        hotkeyManager.endCapture()
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
            recordingStartTime = Date()
            state = .recording
            hotkeyManager.isActive = true
            showPill(state: .recording)
            startLevelUpdates()
            print("[Pipeline] Recording started")
        } catch {
            print("[Pipeline] Failed to start recording: \(error)")
            ToastManager.shared.show(
                .error,
                message: "Failed to start recording: \(error.localizedDescription)"
            )
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
        do {
            // Step 1: Transcribe
            print("[Pipeline] Transcribing...")
            let transcription = try await whisperService.transcribe(fileURL: url)
            let rawText = transcription.text

            if rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await MainActor.run {
                    self.state = .idle
                    completeAndHidePill()
                    print("[Pipeline] Empty transcription, nothing to inject")
                }
                // Clean up temp file
                try? FileManager.default.removeItem(at: url)
                return
            }

            // Step 2: Cleanup (with personal vocabulary)
            print("[Pipeline] Cleaning up...")
            let cleanedText = try await cleanupService.cleanup(
                rawText: rawText,
                vocabulary: self.vocabularyStore.current
            )

            if cleanedText.isEmpty {
                await MainActor.run {
                    self.state = .idle
                    completeAndHidePill()
                    print("[Pipeline] Cleaned text is empty, nothing to inject")
                }
                try? FileManager.default.removeItem(at: url)
                return
            }

            // Step 3: Inject text
            let duration = self.recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
            await MainActor.run {
                print("[Pipeline] Injecting: \(cleanedText)")
                TextInjector.inject(cleanedText)

                // Save to history
                let record = HistoryStore.Record(
                    rawTranscript: rawText,
                    cleanedText: cleanedText,
                    duration: duration,
                    status: .success
                )
                self.historyStore.addRecord(record)

                self.state = .idle
                completeAndHidePill()
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
        // Freeze the trickle in place so it doesn't keep creeping toward 95%
        // during the pill's fade-out (would visually read as success).
        pillVC?.freezeProgressAnimation()
        hidePill()

        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0

        // Save audio to history for retry
        if let historyURL = audioRecorder.moveToHistory(audioURL) {
            let record = HistoryStore.Record(
                rawTranscript: "",
                cleanedText: "",
                duration: duration,
                audioFilePath: historyURL.path,
                status: .failed
            )
            let recordID = record.id
            historyStore.addRecord(record)

            // Toast is 320pt wide — filenames truncate to "…". The history list
            // already surfaces the file, so just confirm persistence here.
            ToastManager.shared.show(
                .error,
                message: "\(message) · Audio saved to history",
                onRetry: { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self = self,
                              let updated = self.historyStore.records.first(where: { $0.id == recordID })
                        else { return }
                        self.retry(record: updated, output: .inject)
                    }
                }
            )
        } else {
            ToastManager.shared.show(.error, message: message)
        }
    }

    // MARK: - Retry

    /// Retry a previously-failed record. Reads the saved audio, runs ASR +
    /// cleanup again, and routes the cleaned text per `output`. On success the
    /// history record is upgraded in place (failed → success) and the audio
    /// file is removed. On failure the record is left untouched so the user
    /// can retry again.
    @MainActor
    func retry(record: HistoryStore.Record, output: RetryOutput) {
        guard state == .idle else {
            ToastManager.shared.show(.error, message: "正在听写中，请稍后重试")
            return
        }
        guard let path = record.audioFilePath, !path.isEmpty,
              FileManager.default.fileExists(atPath: path)
        else {
            ToastManager.shared.show(.error, message: "音频文件丢失，无法重试")
            return
        }

        let url = URL(fileURLWithPath: path)
        let recordID = record.id

        state = .processing
        showPill(state: .processing)

        Task {
            await processRetry(url: url, recordID: recordID, output: output)
        }
    }

    private func processRetry(url: URL, recordID: UUID, output: RetryOutput) async {
        do {
            let transcription = try await whisperService.transcribe(fileURL: url)
            let raw = transcription.text

            if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await MainActor.run {
                    self.state = .idle
                    self.completeAndHidePill()
                    ToastManager.shared.show(.error, message: "重试结果为空")
                }
                return
            }

            let cleaned = try await cleanupService.cleanup(
                rawText: raw,
                vocabulary: self.vocabularyStore.current
            )

            await MainActor.run {
                switch output {
                case .inject:
                    TextInjector.inject(cleaned)
                case .clipboard:
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(cleaned, forType: .string)
                    ToastManager.shared.show(.info, message: "已复制到剪贴板")
                }

                // Upgrade the record in place. Drop audioFilePath since the
                // wav is about to be deleted — `isRetryable` will then read false.
                self.historyStore.updateRecord(id: recordID) { rec in
                    rec.rawTranscript = raw
                    rec.cleanedText = cleaned
                    rec.status = .success
                    rec.audioFilePath = nil
                }
                try? FileManager.default.removeItem(at: url)

                self.state = .idle
                self.completeAndHidePill()
            }
        } catch {
            await MainActor.run {
                self.state = .idle
                self.pillVC?.freezeProgressAnimation()
                self.hidePill()
                // Re-arm retry from the (still failed) record so the toast
                // keeps offering the action across multiple attempts.
                ToastManager.shared.show(
                    .error,
                    message: "重试失败：\(error.localizedDescription)",
                    onRetry: { [weak self] in
                        Task { @MainActor [weak self] in
                            guard let self = self,
                                  let again = self.historyStore.records.first(where: { $0.id == recordID })
                            else { return }
                            self.retry(record: again, output: output)
                        }
                    }
                )
            }
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

        guard let panel = FloatingPillPanel.create() else {
            print("[Pipeline] No screen available for pill panel")
            return
        }
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

    /// Complete the processing progress bar (jump to 100%) before hiding the pill.
    /// Used on the happy path after ASR + cleanup succeed and text is injected.
    private func completeAndHidePill() {
        guard let vc = pillVC else {
            hidePill()
            return
        }
        vc.completeProgressAnimation { [weak self] in
            self?.hidePill()
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
        let escapedBody = body
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedTitle = title
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = [
            "-e",
            "display notification \"\(escapedBody)\" with title \"\(escapedTitle)\"",
        ]
        try? task.run()
    }
}
