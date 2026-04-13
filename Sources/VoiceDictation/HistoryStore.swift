import Combine
import Foundation

/// Persists dictation history records to ~/.voice-dictation/history.json.
/// Observable for SwiftUI integration.
final class HistoryStore: ObservableObject {

    /// A single dictation record.
    struct Record: Codable, Identifiable, Equatable {
        let id: UUID
        var rawTranscript: String
        var cleanedText: String
        var timestamp: Date
        var duration: TimeInterval
        var audioFilePath: String?
        var status: Status

        enum Status: String, Codable {
            case success
            case failed
        }

        init(
            id: UUID = UUID(),
            rawTranscript: String,
            cleanedText: String,
            timestamp: Date = Date(),
            duration: TimeInterval,
            audioFilePath: String? = nil,
            status: Status = .success
        ) {
            self.id = id
            self.rawTranscript = rawTranscript
            self.cleanedText = cleanedText
            self.timestamp = timestamp
            self.duration = duration
            self.audioFilePath = audioFilePath
            self.status = status
        }
    }

    /// All records, sorted by timestamp descending (newest first).
    @Published private(set) var records: [Record] = []

    private let fileURL: URL
    private let directoryURL: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.directoryURL = home.appendingPathComponent(".voice-dictation")
        self.fileURL = directoryURL.appendingPathComponent("history.json")
    }

    // MARK: - Public API

    /// Load history from disk. Call once at startup.
    func load() {
        ensureDirectoryExists()

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            records = []
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loaded = try decoder.decode([Record].self, from: data)
            records = loaded.sorted { $0.timestamp > $1.timestamp }
            print("[HistoryStore] Loaded \(records.count) records")
        } catch {
            print("[HistoryStore] Failed to parse history: \(error)")
            records = []
        }
    }

    /// Add a new record and persist.
    func addRecord(_ record: Record) {
        records.insert(record, at: 0) // newest first
        saveToDisk()
        print("[HistoryStore] Added record: \(record.id)")
    }

    /// Delete a record by ID.
    func deleteRecord(id: UUID) {
        records.removeAll { $0.id == id }
        saveToDisk()
    }

    /// Delete records at given indices (for SwiftUI list).
    func deleteRecords(at indices: [Int]) {
        let idsToRemove = indices.compactMap { idx -> UUID? in
            guard records.indices.contains(idx) else { return nil }
            return records[idx].id
        }
        records.removeAll { idsToRemove.contains($0.id) }
        saveToDisk()
    }

    /// Full-text search across rawTranscript and cleanedText.
    /// Returns filtered records matching query (case-insensitive).
    func search(query: String) -> [Record] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return records }
        return records.filter {
            $0.rawTranscript.lowercased().contains(q)
            || $0.cleanedText.lowercased().contains(q)
        }
    }

    // MARK: - Private

    private func ensureDirectoryExists() {
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    private func saveToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[HistoryStore] Failed to save: \(error)")
        }
    }
}
