import SwiftUI

/// History list screen: search bar + scrollable list of dictation records.
struct HistoryListView: View {
    @ObservedObject var historyStore: HistoryStore
    @Binding var selectedRecordID: UUID?
    /// Invoked when the user taps "Retry" on a failed history card.
    /// Wired to `DictationPipeline.retry(record:, output: .clipboard)` from
    /// the app delegate. Optional so the view stays previewable.
    var onRetry: ((HistoryStore.Record) -> Void)? = nil
    @State private var searchText = ""

    private var filteredRecords: [HistoryStore.Record] {
        historyStore.search(query: searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Theme.textTertiary)
                    .font(.system(size: 13))
                TextField("搜索历史...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Theme.textTertiary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除搜索")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            // Records list
            if filteredRecords.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: searchText.isEmpty ? "clock" : "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(Theme.textTertiary)
                    Text(searchText.isEmpty ? "暂无历史记录" : "未找到匹配记录")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredRecords) { record in
                            HistoryCardView(
                                record: record,
                                isSelected: selectedRecordID == record.id,
                                onSelect: { selectedRecordID = record.id },
                                onCopy: { copyToClipboard(record.cleanedText) },
                                onDelete: { historyStore.deleteRecord(id: record.id) },
                                onRetry: record.isRetryable
                                    ? { onRetry?(record) }
                                    : nil
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .background(Theme.bgBase)
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Individual history card in the list.
struct HistoryCardView: View {
    let record: HistoryStore.Record
    let isSelected: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    /// Optional retry handler. Nil means hide the button (success records or
    /// failed records whose audio file is gone).
    var onRetry: (() -> Void)? = nil

    @State private var isHovered = false
    @State private var showCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Main text
            if record.status == .failed {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Theme.cancel)
                        .font(.system(size: 12))
                    Text("转录失败 — 音频已保存可重试")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.cancel)
                }
            } else {
                Text(record.cleanedText)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }

            // Bottom row: timestamp + timing badges + actions
            HStack(spacing: 8) {
                Text(formatTimestamp(record.timestamp))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)

                TimingBadgeRow(record: record)

                Spacer()

                if record.status == .success {
                    Button(action: {
                        onCopy()
                        showCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showCopied = false
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11))
                            if showCopied {
                                Text("已复制")
                                    .font(.system(size: 11))
                            }
                        }
                        .foregroundColor(showCopied ? Theme.confirm : Theme.textSecondary)
                        // padding turns the gap between icon and text into hit area
                        // (.plain buttons hit-test visible pixels only).
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("复制")
                }

                if let retry = onRetry {
                    Button(action: retry) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                            Text("重试")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(Theme.accent)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("重试")
                }

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除")
            }
        }
        .padding(14)
        .background(isHovered ? Theme.bgCardHover : Theme.bgCard)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Theme.accent.opacity(0.5) : Theme.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 3, y: 1)
        .onHover { hovering in isHovered = hovering }
        .onTapGesture { onSelect() }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            return "今天 " + formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "HH:mm"
            return "昨天 " + formatter.string(from: date)
        } else {
            formatter.dateFormat = "M月d日 HH:mm"
            return formatter.string(from: date)
        }
    }
}

/// Two-capsule timing summary for a history card (variant B).
/// 🎙 录音 capsule + ⚙ 处理 capsule. Falls back gracefully when latency
/// fields are missing (old records pre-dating the per-stage timing change,
/// or failed records where a stage never completed).
private struct TimingBadgeRow: View {
    let record: HistoryStore.Record

    var body: some View {
        HStack(spacing: 5) {
            if let rec = record.recordDuration {
                TimingBadge(
                    sfSymbol: "mic.fill",
                    text: formatLatency(rec),
                    style: .record
                )
            } else if record.status == .success {
                // Old success record without per-stage data — collapse to one
                // neutral pill showing the legacy total duration.
                TimingBadge(
                    sfSymbol: "clock",
                    text: formatLatency(record.duration),
                    style: .fallback
                )
            }

            switch record.status {
            case .success:
                if let processing = processingLatency {
                    TimingBadge(
                        sfSymbol: "gearshape.fill",
                        text: formatLatency(processing),
                        style: .process
                    )
                }
            case .failed:
                TimingBadge(
                    sfSymbol: "xmark",
                    text: "失败",
                    style: .failed
                )
            }
        }
    }

    /// Sum of the per-stage processing latencies, or nil if none recorded.
    private var processingLatency: TimeInterval? {
        let parts: [TimeInterval] = [
            record.asrLatency,
            record.llmLatency,
            record.injectLatency
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.reduce(0, +)
    }

    private func formatLatency(_ s: TimeInterval) -> String {
        if s < 10 { return String(format: "%.1fs", s) }
        if s < 60 { return String(format: "%.0fs", s) }
        let m = Int(s) / 60
        let r = Int(s) % 60
        return "\(m)m\(r)s"
    }
}

/// One capsule badge in the timing row. Uses Theme tokens; tints derive from
/// the existing cancel (orange) / confirm (green) / warn (amber) palette so
/// the badges stay visually consistent with the rest of the app.
struct TimingBadge: View {
    enum Style {
        case record    // 录音 — warm orange (cancel hue, low opacity)
        case process   // 处理 — muted green (confirm hue)
        case asr       // ASR — confirm green (detail row)
        case llm       // LLM — warn amber (detail row)
        case inject    // 注入 — neutral grey (detail row)
        case total     // 总 — filled dark (detail row, anchor)
        case failed    // 失败 — warn amber
        case fallback  // 旧记录无分段 — neutral grey
    }

    let sfSymbol: String?
    let text: String
    let style: Style

    init(sfSymbol: String? = nil, text: String, style: Style) {
        self.sfSymbol = sfSymbol
        self.text = text
        self.style = style
    }

    var body: some View {
        HStack(spacing: 4) {
            if let sfSymbol = sfSymbol {
                Image(systemName: sfSymbol)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
        }
        .foregroundColor(foreground)
        .padding(.leading, sfSymbol == nil ? 8 : 6)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous).fill(background)
        )
        .overlay(
            Capsule(style: .continuous).stroke(borderColor, lineWidth: 1)
        )
    }

    private var foreground: Color {
        switch style {
        case .record:   return Theme.cancel
        case .process:  return Theme.confirm
        case .asr:      return Theme.confirm
        case .llm:      return Theme.warn
        case .inject:   return Theme.textSecondary
        case .total:    return Theme.bgDeep
        case .failed:   return Theme.warn
        case .fallback: return Theme.textSecondary
        }
    }

    private var background: Color {
        switch style {
        case .record:   return Theme.cancel.opacity(0.09)
        case .process:  return Theme.confirm.opacity(0.10)
        case .asr:      return Theme.confirm.opacity(0.10)
        case .llm:      return Theme.warnBg
        case .inject:   return Theme.textSecondary.opacity(0.10)
        case .total:    return Theme.textPrimary
        case .failed:   return Theme.warnBg
        case .fallback: return Theme.bgSurface
        }
    }

    private var borderColor: Color {
        switch style {
        case .record:   return Theme.cancel.opacity(0.18)
        case .process:  return Theme.confirm.opacity(0.22)
        case .asr:      return Theme.confirm.opacity(0.22)
        case .llm:      return Theme.warn.opacity(0.24)
        case .inject:   return Theme.textSecondary.opacity(0.20)
        case .total:    return Theme.textPrimary
        case .failed:   return Theme.warn.opacity(0.22)
        case .fallback: return Theme.border
        }
    }
}

/// Latency formatter shared between card and detail rows.
func formatLatencyShort(_ s: TimeInterval) -> String {
    if s < 10 { return String(format: "%.1fs", s) }
    if s < 60 { return String(format: "%.0fs", s) }
    let m = Int(s) / 60
    let r = Int(s) % 60
    return "\(m)m\(r)s"
}
