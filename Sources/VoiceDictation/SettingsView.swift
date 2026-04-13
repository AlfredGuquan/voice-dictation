import SwiftUI

/// Settings screen: hotkey config, API key, about.
struct SettingsView: View {
    @State private var apiKeyDisplay = ""
    @State private var isEditingApiKey = false
    @State private var editedApiKey = ""

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
                            Text("右 Option")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(Theme.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Theme.bgSurface)
                                .cornerRadius(6)
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

                        Text("快捷键通过全局事件监听实现，无法在此修改")
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
        try? FileManager.default.createDirectory(at: envDir, withIntermediateDirectories: true)
        try? content.write(to: envFile, atomically: true, encoding: .utf8)

        isEditingApiKey = false
        loadApiKeyDisplay()

        print("[Settings] API key updated")
    }
}
