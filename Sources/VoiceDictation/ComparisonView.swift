import SwiftUI

/// Side-by-side comparison of raw transcript vs cleaned text.
struct ComparisonView: View {
    let record: HistoryStore.Record
    let onBack: () -> Void

    @State private var showCopied = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with back button
            VStack(alignment: .leading, spacing: 8) {
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

                // Per-stage latency badges. Hidden if the record predates the
                // change (no fields filled) — falls back to a single "总 X.Xs"
                // capsule to keep the header alignment consistent.
                DetailTimingRow(record: record)
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
                        Text(diffAttributedString)
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textSecondary)
                            .lineSpacing(8)
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

    private var diffAttributedString: AttributedString {
        let segments = Differ.diff(
            original: record.rawTranscript,
            cleaned: record.cleanedText
        )
        var result = AttributedString()
        for seg in segments {
            var piece = AttributedString(seg.text)
            switch seg.kind {
            case .unchanged:
                piece.foregroundColor = Theme.textSecondary
            case .removed:
                piece.foregroundColor = Theme.diffRemovedText
                piece.backgroundColor = Theme.diffRemoved
                piece.strikethroughStyle = .single
                piece.font = .system(size: 14, weight: .medium)
            }
            result.append(piece)
        }
        return result
    }
}

/// Five-capsule per-stage latency strip for the detail header (variant B).
/// Layout: 录音 · ASR · LLM · 注入 · 总
/// Falls back to a single "总 X.Xs" pill when the record predates per-stage
/// instrumentation (`recordDuration` is the canonical "this record has new
/// timing" probe — if it's nil, we collapse to legacy display).
private struct DetailTimingRow: View {
    let record: HistoryStore.Record

    var body: some View {
        if record.recordDuration == nil
            && record.asrLatency == nil
            && record.llmLatency == nil
            && record.injectLatency == nil
        {
            // Legacy record — single capsule with the old `duration`.
            HStack(spacing: 5) {
                TimingBadge(
                    text: "总 \(formatLatencyShort(record.duration))",
                    style: .total
                )
            }
        } else {
            HStack(spacing: 5) {
                if let rec = record.recordDuration {
                    TimingBadge(
                        sfSymbol: "mic.fill",
                        text: "录音 \(formatLatencyShort(rec))",
                        style: .record
                    )
                }
                if let asr = record.asrLatency {
                    TimingBadge(text: "ASR \(formatLatencyShort(asr))", style: .asr)
                }
                if let llm = record.llmLatency {
                    TimingBadge(text: "LLM \(formatLatencyShort(llm))", style: .llm)
                }
                if let inj = record.injectLatency {
                    TimingBadge(text: "注入 \(formatLatencyShort(inj))", style: .inject)
                }
                if let total = totalLatency {
                    TimingBadge(text: "总 \(formatLatencyShort(total))", style: .total)
                }
            }
        }
    }

    /// Best-effort total: sum of all known stages. If a stage is nil (failed
    /// before that stage completed), we omit the total to avoid implying a
    /// number that's missing components.
    private var totalLatency: TimeInterval? {
        guard
            let rec = record.recordDuration,
            let asr = record.asrLatency,
            let llm = record.llmLatency,
            let inj = record.injectLatency
        else { return nil }
        return rec + asr + llm + inj
    }
}
