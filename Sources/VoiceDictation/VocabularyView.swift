import SwiftUI

/// Vocabulary management UI: recognition words and replacement mappings.
struct VocabularyView: View {
    let vocabularyStore: VocabularyStore

    @State private var vocabulary: VocabularyStore.Vocabulary = .empty
    @State private var selectedTab = 0  // 0 = recognition, 1 = replacements
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            HStack(spacing: 0) {
                TabButton(title: "识别词", isSelected: selectedTab == 0) {
                    selectedTab = 0
                }
                TabButton(title: "替换映射", isSelected: selectedTab == 1) {
                    selectedTab = 1
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Theme.textTertiary)
                    .font(.system(size: 13))
                TextField("搜索词库...", text: $searchText)
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
            .padding(.top, 12)
            .padding(.bottom, 12)

            // Content
            if selectedTab == 0 {
                RecognitionWordsSection(
                    words: filteredRecognitionWords,
                    onAdd: addRecognitionWord,
                    onDelete: deleteRecognitionWord
                )
            } else {
                ReplacementsSection(
                    replacements: filteredReplacements,
                    onAdd: addReplacement,
                    onDelete: deleteReplacement,
                    onEdit: editReplacement
                )
            }
        }
        .background(Theme.bgBase)
        .onAppear { vocabulary = vocabularyStore.current }
    }

    // MARK: - Filtered data

    private var filteredRecognitionWords: [String] {
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return vocabulary.recognitionWords }
        return vocabulary.recognitionWords.filter { $0.lowercased().contains(q) }
    }

    private var filteredReplacements: [(key: String, value: String)] {
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        let all = vocabulary.replacements.map { (key: $0.key, value: $0.value) }
            .sorted { $0.key < $1.key }
        guard !q.isEmpty else { return all }
        return all.filter { $0.key.lowercased().contains(q) || $0.value.lowercased().contains(q) }
    }

    // MARK: - Actions

    private func addRecognitionWord(_ word: String) {
        guard !word.isEmpty, !vocabulary.recognitionWords.contains(word) else { return }
        vocabulary.recognitionWords.append(word)
        saveVocabulary()
    }

    private func deleteRecognitionWord(_ word: String) {
        vocabulary.recognitionWords.removeAll { $0 == word }
        saveVocabulary()
    }

    private func addReplacement(trigger: String, replacement: String) {
        guard !trigger.isEmpty, !replacement.isEmpty else { return }
        vocabulary.replacements[trigger] = replacement
        saveVocabulary()
    }

    private func deleteReplacement(trigger: String) {
        vocabulary.replacements.removeValue(forKey: trigger)
        saveVocabulary()
    }

    private func editReplacement(oldTrigger: String, newTrigger: String, newReplacement: String) {
        if oldTrigger != newTrigger {
            vocabulary.replacements.removeValue(forKey: oldTrigger)
        }
        vocabulary.replacements[newTrigger] = newReplacement
        saveVocabulary()
    }

    private func saveVocabulary() {
        do {
            try vocabularyStore.save(vocabulary)
            // File watcher will trigger reload, but update local state immediately
        } catch {
            print("[VocabularyView] Failed to save: \(error)")
        }
    }
}

// MARK: - Tab Button

private struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? Theme.accent : Theme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Theme.accent.opacity(0.1) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recognition Words Section

private struct RecognitionWordsSection: View {
    let words: [String]
    let onAdd: (String) -> Void
    let onDelete: (String) -> Void

    @State private var newWord = ""
    @State private var isAdding = false

    var body: some View {
        VStack(spacing: 0) {
            // Add button row
            HStack {
                Spacer()
                Button(action: { isAdding = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12))
                        Text("添加识别词")
                            .font(.system(size: 13))
                    }
                    .foregroundColor(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            // Add row (inline)
            if isAdding {
                HStack(spacing: 8) {
                    TextField("输入识别词...", text: $newWord)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Theme.border, lineWidth: 1)
                        )
                        .onSubmit {
                            commitAdd()
                        }

                    Button("添加") { commitAdd() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.accent)

                    Button("取消") {
                        newWord = ""
                        isAdding = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            // Words list
            if words.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 28))
                        .foregroundColor(Theme.textTertiary)
                    Text("暂无识别词")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textSecondary)
                    Text("添加专有名词以提升识别准确率")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textTertiary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(words, id: \.self) { word in
                            HStack {
                                Text(word)
                                    .font(.system(size: 13))
                                    .foregroundColor(Theme.textPrimary)
                                Spacer()
                                Button(action: { onDelete(word) }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundColor(Theme.textTertiary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Theme.bgCard)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Theme.border, lineWidth: 0.5)
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    private func commitAdd() {
        let trimmed = newWord.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            onAdd(trimmed)
        }
        newWord = ""
        isAdding = false
    }
}

// MARK: - Replacements Section

private struct ReplacementsSection: View {
    let replacements: [(key: String, value: String)]
    let onAdd: (String, String) -> Void
    let onDelete: (String) -> Void
    let onEdit: (String, String, String) -> Void

    @State private var isAdding = false
    @State private var newTrigger = ""
    @State private var newReplacement = ""

    var body: some View {
        VStack(spacing: 0) {
            // Add button row
            HStack {
                // Column headers
                HStack(spacing: 0) {
                    Text("触发词")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("替换为")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer().frame(width: 30)
                }

                Button(action: { isAdding = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12))
                        Text("添加")
                            .font(.system(size: 13))
                    }
                    .foregroundColor(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            // Add row
            if isAdding {
                HStack(spacing: 8) {
                    TextField("触发词", text: $newTrigger)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Theme.border, lineWidth: 1)
                        )

                    Image(systemName: "arrow.right")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)

                    TextField("替换为", text: $newReplacement)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Theme.border, lineWidth: 1)
                        )
                        .onSubmit { commitAdd() }

                    Button("添加") { commitAdd() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.accent)

                    Button("取消") {
                        newTrigger = ""
                        newReplacement = ""
                        isAdding = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            // Replacements list
            if replacements.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 28))
                        .foregroundColor(Theme.textTertiary)
                    Text("暂无替换映射")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textSecondary)
                    Text("添加 \"说X写Y\" 的替换规则")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textTertiary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(replacements, id: \.key) { item in
                            ReplacementRow(
                                trigger: item.key,
                                replacement: item.value,
                                onDelete: { onDelete(item.key) },
                                onEdit: { newTrig, newRepl in
                                    onEdit(item.key, newTrig, newRepl)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    private func commitAdd() {
        let t = newTrigger.trimmingCharacters(in: .whitespaces)
        let r = newReplacement.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty && !r.isEmpty {
            onAdd(t, r)
        }
        newTrigger = ""
        newReplacement = ""
        isAdding = false
    }
}

/// Editable row for a replacement mapping.
private struct ReplacementRow: View {
    let trigger: String
    let replacement: String
    let onDelete: () -> Void
    let onEdit: (String, String) -> Void

    @State private var isEditing = false
    @State private var editTrigger = ""
    @State private var editReplacement = ""

    var body: some View {
        HStack(spacing: 8) {
            if isEditing {
                TextField("触发词", text: $editTrigger)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Theme.accent.opacity(0.5), lineWidth: 1)
                    )
                    .frame(maxWidth: .infinity)

                Image(systemName: "arrow.right")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)

                TextField("替换为", text: $editReplacement)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Theme.accent.opacity(0.5), lineWidth: 1)
                    )
                    .frame(maxWidth: .infinity)
                    .onSubmit { commitEdit() }

                Button(action: commitEdit) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.confirm)
                }
                .buttonStyle(.plain)

                Button(action: { isEditing = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            } else {
                Text(trigger)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.right")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)

                Text(replacement)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: {
                    editTrigger = trigger
                    editReplacement = replacement
                    isEditing = true
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                }
                .buttonStyle(.plain)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.bgCard)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }

    private func commitEdit() {
        let t = editTrigger.trimmingCharacters(in: .whitespaces)
        let r = editReplacement.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty && !r.isEmpty {
            onEdit(t, r)
        }
        isEditing = false
    }
}
