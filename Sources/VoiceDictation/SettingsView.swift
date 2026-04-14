import SwiftUI
import AppKit

/// Settings screen: hotkey config, API key, about.
struct SettingsView: View {
    @State private var apiKeyDisplay = ""
    @State private var isEditingApiKey = false
    @State private var editedApiKey = ""
    @State private var saveError: String?
    @State private var showSaveError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Hotkey section
                settingsSection(title: "快捷键", icon: "keyboard") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("听写快捷键")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            HotkeyRecorderControl()
                        }

                        HStack {
                            Text("取消录音")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            Text("Esc")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(Theme.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Theme.bgSurface)
                                .cornerRadius(6)
                        }

                        Text("点击右侧快捷键进入录制模式，录制期间按 Esc 取消。冲突只提示不阻止保存。")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary)
                    }
                }

                // API Key section
                settingsSection(title: "API 配置", icon: "key") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("OpenAI API Key")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            if isEditingApiKey {
                                TextField("sk-...", text: $editedApiKey)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white)
                                    .cornerRadius(4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Theme.accent.opacity(0.5), lineWidth: 1)
                                    )
                                    .frame(maxWidth: 280)
                                    .onSubmit { saveApiKey() }

                                Button("保存") { saveApiKey() }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Theme.accent)

                                Button("取消") { isEditingApiKey = false }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.textSecondary)
                            } else {
                                Text(apiKeyDisplay)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(Theme.textSecondary)

                                Button(action: {
                                    editedApiKey = loadFullApiKey()
                                    isEditingApiKey = true
                                }) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 11))
                                        .foregroundColor(Theme.accent)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Text("密钥存储在 ~/.voice-dictation/.env 文件中")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary)
                    }
                }

                // About section
                settingsSection(title: "关于", icon: "info.circle") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Voice Dictation")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            Text("v0.1.0")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(Theme.textTertiary)
                        }
                        Text("Mac 语音输入法 — 用说话替代打字")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                    }
                }

                Spacer()
            }
            .padding(20)
        }
        .background(Theme.bgBase)
        .onAppear { loadApiKeyDisplay() }
        .alert("保存失败", isPresented: $showSaveError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(saveError ?? "未知错误")
        }
    }

    // MARK: - Section builder

    @ViewBuilder
    private func settingsSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.textPrimary)

            content()
                .padding(16)
                .background(Theme.bgCard)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.border, lineWidth: 0.5)
                )
        }
    }

    // MARK: - API Key management

    private func loadApiKeyDisplay() {
        let env = EnvLoader.load()
        if let key = env["OPENAI_API_KEY"], key.count > 8 {
            apiKeyDisplay = key.prefix(4) + "..." + key.suffix(4)
        } else if let key = env["OPENAI_API_KEY"], !key.isEmpty {
            apiKeyDisplay = "****"
        } else {
            apiKeyDisplay = "未设置"
        }
    }

    private func loadFullApiKey() -> String {
        let env = EnvLoader.load()
        return env["OPENAI_API_KEY"] ?? ""
    }

    // (HotkeyRecorderControl defined below)

    private func saveApiKey() {
        let key = editedApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            isEditingApiKey = false
            return
        }

        let envDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".voice-dictation")
        let envFile = envDir.appendingPathComponent(".env")

        // Read existing .env, update or append OPENAI_API_KEY
        var lines: [String] = []
        if let existing = try? String(contentsOf: envFile, encoding: .utf8) {
            lines = existing.components(separatedBy: .newlines)
        }

        var found = false
        for (i, line) in lines.enumerated() {
            if line.hasPrefix("OPENAI_API_KEY") {
                lines[i] = "OPENAI_API_KEY=\(key)"
                found = true
                break
            }
        }
        if !found {
            lines.append("OPENAI_API_KEY=\(key)")
        }

        // Remove trailing empty lines
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeLast()
        }

        let content = lines.joined(separator: "\n") + "\n"
        do {
            try FileManager.default.createDirectory(at: envDir, withIntermediateDirectories: true)
            try content.write(to: envFile, atomically: true, encoding: .utf8)
            isEditingApiKey = false
            loadApiKeyDisplay()
            print("[Settings] API key updated")
        } catch {
            saveError = error.localizedDescription
            showSaveError = true
            print("[Settings] Failed to save API key: \(error)")
        }
    }
}

// MARK: - Hotkey recorder control
//
// Four visual states (v03-brief F9):
//   default   — shows current hotkey; click to start recording.
//   recording — "按下要录制的键…" with pulsing accent border. Esc cancels.
//   saved     — confirm-green 1.2s flash then falls back to default.
//   conflict  — warn-amber border + inline conflict hint (still saveable).
//
// Save path:
//   classify NSEvent → HotkeyType  → Config.hotkey = ...
//   → post .hotkeyConfigChanged   → DictationPipeline.reload
private struct HotkeyRecorderControl: View {
    private enum Phase: Equatable {
        case idle
        case recording
        case justSaved
    }

    @State private var currentHotkey: HotkeyManager.HotkeyType = Config.hotkey
    @State private var phase: Phase = .idle
    @State private var eventMonitor: Any?
    @State private var conflictHint: String? = nil

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button(action: beginRecording) {
                Text(chipText)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(chipForeground)
                    .frame(minWidth: 140, minHeight: 28 - 2)  // account for border stroke
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(chipBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(borderColor, lineWidth: phase == .idle ? 1 : 1.5)
                    )
            }
            .buttonStyle(.plain)
            .disabled(phase == .recording)  // clicking again while recording is a no-op

            if let hint = conflictHint {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 260, alignment: .trailing)
            }
        }
        .onDisappear { endRecording(cancelled: true) }
    }

    // MARK: - Visual tokens

    private var chipText: String {
        switch phase {
        case .idle, .justSaved:
            return currentHotkey.displayName
        case .recording:
            return "按下要录制的键…"
        }
    }

    private var chipForeground: Color {
        switch phase {
        case .idle:      return Theme.textSecondary
        case .recording: return Theme.accent
        case .justSaved: return Theme.confirm
        }
    }

    private var chipBackground: Color {
        switch phase {
        case .idle:      return Theme.bgSurface
        case .recording: return Theme.bgSurface
        case .justSaved: return Theme.confirmBg
        }
    }

    private var borderColor: Color {
        if conflictHint != nil && phase == .justSaved { return Theme.warn }
        switch phase {
        case .idle:      return Theme.border
        case .recording: return Theme.accent
        case .justSaved: return Theme.confirm
        }
    }

    // MARK: - Recording lifecycle

    private func beginRecording() {
        guard phase != .recording else { return }
        phase = .recording
        conflictHint = nil

        // Monitor both keyDown (chord candidates) and flagsChanged (single
        // modifier candidates). .local monitors only trigger while the app
        // window is key, which is exactly what we want — we don't want to
        // capture system-wide keystrokes here.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handleEvent(event)
            // Swallow the event so it doesn't bleed into the main window
            // (e.g. the Settings form's text fields).
            return nil
        }
    }

    private func endRecording(cancelled: Bool) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if cancelled {
            phase = .idle
        }
    }

    private func handleEvent(_ event: NSEvent) {
        // Esc cancels — leaves saved value untouched.
        if event.type == .keyDown && event.keyCode == 53 {
            endRecording(cancelled: true)
            return
        }

        let keyCode = Int64(event.keyCode)
        let cgFlags = event.cgFlags

        // flagsChanged: only fire on a single-modifier press-down. Wait until
        // the user actually holds the modifier (flags != empty for that key).
        if event.type == .flagsChanged {
            // Reject all-empty flags (= key released) — wait for the press.
            let mask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
            let pressed = cgFlags.intersection(mask)
            // For modifier-less flagsChanged triggers (CapsLock=57, Fn=63),
            // accept the first such event.
            let isKnownLoneModifier = [
                Int64(54), 55, 56, 60, 58, 61, 59, 62, 57, 63
            ].contains(keyCode)
            guard isKnownLoneModifier else { return }

            if keyCode == 57 || keyCode == 63 {
                // CapsLock/Fn — no modifier bit; accept immediately.
                commit(HotkeyManager.HotkeyType.singleModifier(keyCode: keyCode))
                return
            }
            // Other modifiers: only on press (pressed == own flag). Release
            // sends another flagsChanged with pressed == [].
            let own = HotkeyManager.modifierFlag(forSingleModifierKeyCode: keyCode)
            if pressed == own && !own.isEmpty {
                commit(HotkeyManager.HotkeyType.singleModifier(keyCode: keyCode))
            }
            return
        }

        // keyDown: must be a chord (has modifiers). Plain letter keys are
        // rejected (no modifier = captures every keystroke, bad UX).
        if event.type == .keyDown {
            if let hotkey = HotkeyManager.classify(keyCode: keyCode, flags: cgFlags) {
                commit(hotkey)
            }
            return
        }
    }

    private func commit(_ hotkey: HotkeyManager.HotkeyType) {
        endRecording(cancelled: false)
        currentHotkey = hotkey
        Config.hotkey = hotkey
        conflictHint = HotkeyManager.conflictDescription(for: hotkey).map { name in
            "此快捷键与 \(name) 冲突 — 本应用将优先响应"
        }
        NotificationCenter.default.post(name: .hotkeyConfigChanged, object: nil)

        // Flash "saved" state for 1.2s, then fall back to idle.
        phase = .justSaved
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if phase == .justSaved { phase = .idle }
        }
    }
}

private extension NSEvent {
    /// Convert NSEvent.modifierFlags → CGEventFlags (raw-value compatible so
    /// we can share KnownConflict/HotkeyType logic with the global event tap).
    var cgFlags: CGEventFlags {
        var out: CGEventFlags = []
        if modifierFlags.contains(.command)   { out.insert(.maskCommand) }
        if modifierFlags.contains(.option)    { out.insert(.maskAlternate) }
        if modifierFlags.contains(.shift)     { out.insert(.maskShift) }
        if modifierFlags.contains(.control)   { out.insert(.maskControl) }
        if modifierFlags.contains(.capsLock)  { out.insert(.maskAlphaShift) }
        return out
    }
}
