import SwiftUI

/// Side-by-side comparison of raw transcript vs cleaned text.
struct ComparisonView: View {
    let record: HistoryStore.Record
    let onBack: () -> Void

    @State private var showCopied = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                        Text("返回列表")
                            .font(.system(size: 13))
                    }
                    .foregroundColor(Theme.accent)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(formatTimestamp(record.timestamp))
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textTertiary)

                Spacer()

                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(record.cleanedText, forType: .string)
                    showCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showCopied = false
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12))
                        Text(showCopied ? "已复制" : "复制")
                            .font(.system(size: 13))
                    }
                    .foregroundColor(showCopied ? Theme.confirm : Theme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Theme.bgBase)

            Divider()
                .background(Theme.border)

            // Side-by-side comparison
            HStack(spacing: 0) {
                // Left: raw transcript
                VStack(alignment: .leading, spacing: 12) {
                    Label("原始转录", systemImage: "waveform")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.textSecondary)

                    ScrollView {
                        Text(record.rawTranscript)
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textSecondary)
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.bgBase.opacity(0.5))

                // Divider
                Rectangle()
                    .fill(Theme.border)
                    .frame(width: 1)

                // Right: cleaned text
                VStack(alignment: .leading, spacing: 12) {
                    Label("清洗后", systemImage: "text.badge.checkmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.confirm)

                    ScrollView {
                        Text(record.cleanedText)
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textPrimary)
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.bgCard.opacity(0.5))
            }
        }
        .background(Theme.bgBase)
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }
}
