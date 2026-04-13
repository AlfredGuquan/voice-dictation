import SwiftUI

/// History list screen: search bar + scrollable list of dictation records.
struct HistoryListView: View {
    @ObservedObject var historyStore: HistoryStore
    @Binding var selectedRecordID: UUID?
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
                                onDelete: { historyStore.deleteRecord(id: record.id) }
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

            // Bottom row: timestamp + duration + actions
            HStack {
                Text(formatTimestamp(record.timestamp))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)

                Text("·")
                    .foregroundColor(Theme.textTertiary)

                Text(formatDuration(record.duration))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)

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
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                }
                .buttonStyle(.plain)
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

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        if seconds < 60 {
            return "\(seconds)秒"
        } else {
            return "\(seconds / 60)分\(seconds % 60)秒"
        }
    }
}
