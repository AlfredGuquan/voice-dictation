#!/usr/bin/env swift

// Tests for the per-stage latency fields added to HistoryStore.Record:
//   recordDuration / asrLatency / llmLatency / injectLatency
// All four are optional so old history.json (without the keys) keeps decoding.

import Foundation

// ----- Inline model (mirrors HistoryStore.Record after the change) -----

struct Record: Codable, Identifiable, Equatable {
    let id: UUID
    var rawTranscript: String
    var cleanedText: String
    var timestamp: Date
    var duration: TimeInterval
    var audioFilePath: String?
    var status: Status

    var recordDuration: TimeInterval?
    var asrLatency: TimeInterval?
    var llmLatency: TimeInterval?
    var injectLatency: TimeInterval?

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

print("=== HistoryStore latency-fields Tests ===\n")

// Test 1: Round-trip with all four latency fields populated
print("[Test 1] Round-trip with all latency fields")
do {
    let record = Record(
        id: UUID(),
        rawTranscript: "raw",
        cleanedText: "clean",
        timestamp: Date(),
        duration: 5.55,
        audioFilePath: nil,
        status: .success,
        recordDuration: 3.2,
        asrLatency: 1.4,
        llmLatency: 0.9,
        injectLatency: 0.05
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(record)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(Record.self, from: data)

    assert(decoded.recordDuration == 3.2, "recordDuration round-trips")
    assert(decoded.asrLatency == 1.4, "asrLatency round-trips")
    assert(decoded.llmLatency == 0.9, "llmLatency round-trips")
    assert(decoded.injectLatency == 0.05, "injectLatency round-trips")
    assert(decoded.duration == 5.55, "old duration field unchanged")
}

// Test 2: Old JSON (no latency keys) decodes with nil fields — backwards compat
print("\n[Test 2] Old JSON without latency keys decodes to nil")
do {
    let oldJSON = """
    {
      "id": "00000000-0000-0000-0000-000000000001",
      "rawTranscript": "old raw",
      "cleanedText": "old clean",
      "timestamp": "2025-01-01T00:00:00Z",
      "duration": 4.2,
      "status": "success"
    }
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(Record.self, from: oldJSON)

    assert(decoded.recordDuration == nil, "old record: recordDuration is nil")
    assert(decoded.asrLatency == nil, "old record: asrLatency is nil")
    assert(decoded.llmLatency == nil, "old record: llmLatency is nil")
    assert(decoded.injectLatency == nil, "old record: injectLatency is nil")
    assert(decoded.duration == 4.2, "old record: duration preserved")
    assert(decoded.cleanedText == "old clean", "old record: cleanedText preserved")
}

// Test 3: Failed record with partial latency (asr completed, llm did not)
print("\n[Test 3] Failed record with partial latency")
do {
    let record = Record(
        id: UUID(),
        rawTranscript: "",
        cleanedText: "",
        timestamp: Date(),
        duration: 13.0,
        audioFilePath: "/tmp/audio.wav",
        status: .failed,
        recordDuration: 2.0,
        asrLatency: 1.1,
        llmLatency: nil,    // LLM never completed
        injectLatency: nil
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(record)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(Record.self, from: data)

    assert(decoded.status == .failed, "status preserved")
    assert(decoded.recordDuration == 2.0, "recordDuration preserved")
    assert(decoded.asrLatency == 1.1, "asrLatency preserved")
    assert(decoded.llmLatency == nil, "llmLatency stays nil for unfinished stage")
    assert(decoded.injectLatency == nil, "injectLatency stays nil")
}

// ----- Summary -----

print("\n=== Results: \(passed) passed, \(failed) failed ===")
if failed > 0 {
    exit(1)
}
