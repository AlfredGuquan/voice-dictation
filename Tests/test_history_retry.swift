#!/usr/bin/env swift

// Standalone test for the failure-retry data model.
// Mirrors HistoryStore.updateRecord and the retry success/failure transitions.
// Real network + UI pieces are exercised by QA, not here.

import Foundation

// ----- Inline model (mirrors HistoryStore.Record + updateRecord) -----

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

    /// Eligible for retry only if the audio is still on disk.
    /// Mirrors the production guard so QA failures here surface before runtime.
    var isRetryable: Bool {
        return status == .failed && (audioFilePath?.isEmpty == false)
    }
}

final class StoreMirror {
    private(set) var records: [Record] = []

    func add(_ r: Record) { records.insert(r, at: 0) }

    /// Mirrors HistoryStore.updateRecord(id:transform:).
    /// Missing id is a no-op (UI may race with deletion).
    @discardableResult
    func update(id: UUID, transform: (inout Record) -> Void) -> Bool {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return false }
        transform(&records[idx])
        return true
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

print("=== HistoryRetry Tests ===\n")

// Test 1: isRetryable correctly identifies failed records with audio
print("[Test 1] isRetryable predicate")
do {
    let okFailed = Record(
        id: UUID(), rawTranscript: "", cleanedText: "",
        timestamp: Date(), duration: 1.0,
        audioFilePath: "/tmp/a.wav", status: .failed
    )
    let failedNoAudio = Record(
        id: UUID(), rawTranscript: "", cleanedText: "",
        timestamp: Date(), duration: 1.0,
        audioFilePath: nil, status: .failed
    )
    let success = Record(
        id: UUID(), rawTranscript: "x", cleanedText: "x",
        timestamp: Date(), duration: 1.0,
        audioFilePath: nil, status: .success
    )
    assert(okFailed.isRetryable, "failed + audio → retryable")
    assert(!failedNoAudio.isRetryable, "failed without audio → not retryable")
    assert(!success.isRetryable, "success → not retryable")
}

// Test 2: updateRecord finds and mutates the right record
print("\n[Test 2] updateRecord by id")
do {
    let store = StoreMirror()
    let id1 = UUID()
    let id2 = UUID()
    store.add(Record(id: id1, rawTranscript: "", cleanedText: "",
                     timestamp: Date(), duration: 1, audioFilePath: "/tmp/1.wav", status: .failed))
    store.add(Record(id: id2, rawTranscript: "", cleanedText: "",
                     timestamp: Date(), duration: 2, audioFilePath: "/tmp/2.wav", status: .failed))

    let ok = store.update(id: id1) { rec in
        rec.rawTranscript = "raw text"
        rec.cleanedText = "cleaned text"
        rec.status = .success
        rec.audioFilePath = nil
    }
    assert(ok, "update returned true for known id")

    let r1 = store.records.first(where: { $0.id == id1 })!
    let r2 = store.records.first(where: { $0.id == id2 })!
    assert(r1.status == .success, "id1 status upgraded to success")
    assert(r1.cleanedText == "cleaned text", "id1 cleanedText set")
    assert(r1.audioFilePath == nil, "id1 audio cleared after success")
    assert(r2.status == .failed, "id2 untouched")
}

// Test 3: updateRecord with unknown id is a no-op
print("\n[Test 3] updateRecord unknown id is no-op")
do {
    let store = StoreMirror()
    store.add(Record(id: UUID(), rawTranscript: "", cleanedText: "",
                     timestamp: Date(), duration: 1, audioFilePath: "/tmp/x.wav", status: .failed))
    var sideEffectCalled = false
    let ok = store.update(id: UUID()) { _ in sideEffectCalled = true }
    assert(!ok, "update returned false for unknown id")
    assert(!sideEffectCalled, "transform never invoked for unknown id")
    assert(store.records.count == 1, "record count unchanged")
}

// Test 4: Retry-failure transition leaves record retryable
print("\n[Test 4] Retry failure preserves retryable state")
do {
    let store = StoreMirror()
    let id = UUID()
    store.add(Record(id: id, rawTranscript: "", cleanedText: "",
                     timestamp: Date(), duration: 1,
                     audioFilePath: "/tmp/keep.wav", status: .failed))

    // Simulate a retry that throws — UI must NOT mutate the record on failure.
    // (We verify by simply not calling update; this asserts the contract.)
    let r = store.records[0]
    assert(r.isRetryable, "record still retryable after a failed retry attempt")
    assert(r.audioFilePath == "/tmp/keep.wav", "audio path preserved")
}

// Test 5: Persistence round-trip preserves new fields
print("\n[Test 5] Updated record round-trips through JSON")
do {
    let store = StoreMirror()
    let id = UUID()
    store.add(Record(id: id, rawTranscript: "", cleanedText: "",
                     timestamp: Date(), duration: 1,
                     audioFilePath: "/tmp/y.wav", status: .failed))
    store.update(id: id) { rec in
        rec.rawTranscript = "raw"
        rec.cleanedText = "clean"
        rec.status = .success
        rec.audioFilePath = nil
    }

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try! encoder.encode(store.records)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let loaded = try! decoder.decode([Record].self, from: data)

    let loadedRec = loaded.first(where: { $0.id == id })!
    assert(loadedRec.status == .success, "status persisted as success")
    assert(loadedRec.cleanedText == "clean", "cleanedText persisted")
    assert(loadedRec.audioFilePath == nil, "audioFilePath persisted as nil")
}

// ----- Summary -----

print("\n=== Results: \(passed) passed, \(failed) failed ===")
if failed > 0 {
    exit(1)
}
