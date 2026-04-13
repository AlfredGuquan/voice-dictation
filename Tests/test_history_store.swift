#!/usr/bin/env swift

// Standalone test for HistoryStore logic.
// Tests JSON serialization, search, and delete operations.

import Foundation

// ----- Inline model (mirrors HistoryStore.Record) -----

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
}

// ----- Test helpers -----

var passed = 0
var failed = 0

func assert(_ condition: Bool, _ msg: String, file: String = #file, line: Int = #line) {
    if condition {
        passed += 1
        print("  PASS: \(msg)")
    } else {
        failed += 1
        print("  FAIL: \(msg) (\(file):\(line))")
    }
}

// ----- Tests -----

print("=== HistoryStore Tests ===\n")

// Test 1: JSON round-trip
print("[Test 1] JSON encode/decode round-trip")
do {
    let record = Record(
        id: UUID(),
        rawTranscript: "嗯，我觉得这个 feature 啊需要一个 API",
        cleanedText: "我觉得这个 feature 需要一个 API",
        timestamp: Date(),
        duration: 5.3,
        audioFilePath: nil,
        status: .success
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode([record])

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode([Record].self, from: data)

    assert(decoded.count == 1, "decoded count is 1")
    assert(decoded[0].id == record.id, "id matches")
    assert(decoded[0].rawTranscript == record.rawTranscript, "rawTranscript matches")
    assert(decoded[0].cleanedText == record.cleanedText, "cleanedText matches")
    assert(decoded[0].status == .success, "status matches")
    assert(decoded[0].duration == 5.3, "duration matches")
}

// Test 2: Failed record with audioFilePath
print("\n[Test 2] Failed record serialization")
do {
    let record = Record(
        id: UUID(),
        rawTranscript: "",
        cleanedText: "",
        timestamp: Date(),
        duration: 3.0,
        audioFilePath: "/Users/test/.voice-dictation/history/audio.wav",
        status: .failed
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(record)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(Record.self, from: data)

    assert(decoded.status == .failed, "status is failed")
    assert(decoded.audioFilePath != nil, "audioFilePath preserved")
    assert(decoded.audioFilePath == "/Users/test/.voice-dictation/history/audio.wav", "audioFilePath matches")
}

// Test 3: Search (case-insensitive)
print("\n[Test 3] Full-text search")
do {
    let records = [
        Record(id: UUID(), rawTranscript: "hello world", cleanedText: "Hello World",
               timestamp: Date(), duration: 1, status: .success),
        Record(id: UUID(), rawTranscript: "Claude Code test", cleanedText: "Claude Code test",
               timestamp: Date(), duration: 2, status: .success),
        Record(id: UUID(), rawTranscript: "其他内容", cleanedText: "其他内容",
               timestamp: Date(), duration: 3, status: .success),
    ]

    func search(_ query: String) -> [Record] {
        let q = query.lowercased()
        guard !q.isEmpty else { return records }
        return records.filter {
            $0.rawTranscript.lowercased().contains(q) || $0.cleanedText.lowercased().contains(q)
        }
    }

    assert(search("claude").count == 1, "search 'claude' finds 1 result")
    assert(search("HELLO").count == 1, "search 'HELLO' finds 1 (case-insensitive)")
    assert(search("").count == 3, "empty search returns all")
    assert(search("不存在").count == 0, "search nonexistent returns 0")
    assert(search("内容").count == 1, "Chinese search works")
}

// Test 4: Delete
print("\n[Test 4] Delete by ID")
do {
    let id1 = UUID()
    let id2 = UUID()
    var records = [
        Record(id: id1, rawTranscript: "a", cleanedText: "a",
               timestamp: Date(), duration: 1, status: .success),
        Record(id: id2, rawTranscript: "b", cleanedText: "b",
               timestamp: Date(), duration: 2, status: .success),
    ]

    records.removeAll { $0.id == id1 }
    assert(records.count == 1, "after delete, count is 1")
    assert(records[0].id == id2, "remaining record is correct")
}

// Test 5: File I/O round-trip
print("\n[Test 5] File write/read round-trip")
do {
    let tempDir = FileManager.default.temporaryDirectory
    let testFile = tempDir.appendingPathComponent("test_history_\(Int(Date().timeIntervalSince1970)).json")

    let records = [
        Record(id: UUID(), rawTranscript: "raw 1", cleanedText: "clean 1",
               timestamp: Date(), duration: 2.5, status: .success),
        Record(id: UUID(), rawTranscript: "", cleanedText: "",
               timestamp: Date(), duration: 1.0, audioFilePath: "/tmp/audio.wav", status: .failed),
    ]

    // Write
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(records)
    try data.write(to: testFile, options: .atomic)

    // Read back
    let readData = try Data(contentsOf: testFile)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let loaded = try decoder.decode([Record].self, from: readData)

    assert(loaded.count == 2, "loaded 2 records from file")
    assert(loaded[0].cleanedText == "clean 1", "first record text matches")
    assert(loaded[1].status == .failed, "second record status matches")

    // Cleanup
    try FileManager.default.removeItem(at: testFile)
    assert(true, "temp file cleaned up")
}

// ----- Summary -----

print("\n=== Results: \(passed) passed, \(failed) failed ===")
if failed > 0 {
    exit(1)
}
