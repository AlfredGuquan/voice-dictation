import Foundation

/// Manages personal vocabulary: recognition words and replacement mappings.
/// File-based storage at ~/.voice-dictation/vocabulary.json, with DispatchSource file watching.
final class VocabularyStore {

    /// The vocabulary data model, matching the JSON format.
    struct Vocabulary: Codable, Equatable {
        var recognitionWords: [String]
        var replacements: [String: String]

        static let empty = Vocabulary(recognitionWords: [], replacements: [:])
    }

    /// Current vocabulary, thread-safe via main actor access pattern.
    /// Consumers read this directly; it's updated automatically on file changes.
    private(set) var current: Vocabulary = .empty

    /// Called on main thread whenever vocabulary changes (load or file-watch reload).
    var onChange: ((Vocabulary) -> Void)?

    private let fileURL: URL
    private let directoryURL: URL
    private var fileSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.directoryURL = home.appendingPathComponent(".voice-dictation")
        self.fileURL = directoryURL.appendingPathComponent("vocabulary.json")
    }

    // MARK: - Public API

    /// Load vocabulary from disk. Creates default file if none exists.
    /// Call once at startup, then file watching handles subsequent changes.
    func load() {
        ensureDirectoryExists()

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            createDefaultFile()
        }

        reloadFromDisk()
        startWatching()
    }

    /// Force a reload from disk (useful for testing).
    func reload() {
        reloadFromDisk()
    }

    /// Save the given vocabulary to disk (used by UI in the future).
    func save(_ vocabulary: Vocabulary) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(vocabulary)
        try data.write(to: fileURL, options: .atomic)
        // File watcher will pick up the change and call reloadFromDisk
    }

    /// Stop file watching. Call on teardown.
    func stopWatching() {
        fileSource?.cancel()
        fileSource = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    deinit {
        stopWatching()
    }

    // MARK: - Prompt fragments for LLM injection

    /// Returns prompt text for recognition words, or nil if empty.
    func recognitionWordsPrompt() -> String? {
        guard !current.recognitionWords.isEmpty else { return nil }
        let words = current.recognitionWords.joined(separator: "、")
        return "以下专有名词必须保持原样：\(words)"
    }

    /// Returns prompt text for replacement mappings, or nil if empty.
    func replacementsPrompt() -> String? {
        guard !current.replacements.isEmpty else { return nil }
        let lines = current.replacements.map { "\($0.key) → \($0.value)" }
        return "以下词语需要替换：\(lines.joined(separator: "、"))"
    }

    // MARK: - Private

    private func ensureDirectoryExists() {
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    private func createDefaultFile() {
        let defaultVocab = Vocabulary(
            recognitionWords: ["Claude Code", "Anthropic"],
            replacements: ["Cloud": "Claude"]
        )
        do {
            try save(defaultVocab)
            print("[Vocabulary] Created default vocabulary file at \(fileURL.path)")
        } catch {
            print("[Vocabulary] Failed to create default file: \(error)")
        }
    }

    private func reloadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("[Vocabulary] File not found, using empty vocabulary")
            current = .empty
            onChange?(current)
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let vocab = try JSONDecoder().decode(Vocabulary.self, from: data)
            current = vocab
            print("[Vocabulary] Loaded: \(vocab.recognitionWords.count) words, \(vocab.replacements.count) replacements")
            onChange?(current)
        } catch {
            print("[Vocabulary] Failed to parse vocabulary file: \(error)")
            // Keep current vocabulary on parse error
        }
    }

    // MARK: - File Watching

    private func startWatching() {
        stopWatching()

        fileDescriptor = Darwin.open(fileURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("[Vocabulary] Cannot open file for watching: \(fileURL.path)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .attrib],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) {
                // File was replaced (atomic write does delete+rename)
                // Restart watching on the new file
                self.restartWatching()
            } else {
                self.reloadFromDisk()
            }
        }

        source.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }

        source.resume()
        self.fileSource = source
        print("[Vocabulary] Watching for file changes: \(fileURL.path)")
    }

    private func restartWatching() {
        // Brief delay to let the new file settle (atomic writes do rename)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            self.reloadFromDisk()
            self.startWatching()
        }
    }
}
