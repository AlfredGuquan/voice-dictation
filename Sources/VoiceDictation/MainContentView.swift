import SwiftUI

/// Root view for the main application window.
/// Sidebar navigation with three sections: History, Vocabulary, Settings.
struct MainContentView: View {
    let historyStore: HistoryStore
    let vocabularyStore: VocabularyStore

    @State private var selectedSection: SidebarSection = .history
    @State private var selectedRecordID: UUID?

    enum SidebarSection: String, CaseIterable {
        case history = "历史"
        case vocabulary = "词库"
        case settings = "设置"

        var icon: String {
            switch self {
            case .history: return "clock"
            case .vocabulary: return "book"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            sidebar

            // Divider
            Rectangle()
                .fill(Theme.border)
                .frame(width: 1)

            // Content area
            contentArea
        }
        .frame(minWidth: 850, minHeight: 520)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            // App title
            Text("Voice Dictation")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 16)

            ForEach(SidebarSection.allCases, id: \.self) { section in
                sidebarItem(section: section)
            }

            Spacer()
        }
        .frame(width: 180)
        .background(Theme.bgSidebar)
    }

    private func sidebarItem(section: SidebarSection) -> some View {
        Button(action: {
            selectedSection = section
            if section != .history {
                selectedRecordID = nil
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 14))
                    .frame(width: 20)
                Text(section.rawValue)
                    .font(.system(size: 13))
                Spacer()
            }
            .foregroundColor(selectedSection == section ? Theme.accent : Theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                selectedSection == section
                    ? Theme.accent.opacity(0.1)
                    : Color.clear
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        switch selectedSection {
        case .history:
            historyContent

        case .vocabulary:
            VocabularyView(vocabularyStore: vocabularyStore)

        case .settings:
            SettingsView()
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if let recordID = selectedRecordID,
           let record = historyStore.records.first(where: { $0.id == recordID }) {
            ComparisonView(
                record: record,
                onBack: { selectedRecordID = nil }
            )
        } else {
            HistoryListView(
                historyStore: historyStore,
                selectedRecordID: $selectedRecordID
            )
        }
    }
}
