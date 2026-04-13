#!/usr/bin/env swift
/// Standalone test script for VocabularyStore and LLM prompt building.
/// Run: swift test-vocabulary.swift
/// Tests file I/O, JSON parsing, prompt generation, and file-change detection.

import Foundation

// ============================================================
// Inline minimal copies of types under test (since we can't import executable target)
// ============================================================

struct Vocabulary: Codable, Equatable {
    var recognitionWords: [String]
    var replacements: [String: String]

    static let empty = Vocabulary(recognitionWords: [], replacements: [:])
}

// ============================================================
// Test helpers
// ============================================================

var passed = 0
var failed = 0

func assert(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    if condition {
        passed += 1
        print("  PASS: \(message)")
    } else {
        failed += 1
        print("  FAIL: \(message) (at line \(line))")
    }
}

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String, file: String = #file, line: Int = #line) {
    if a == b {
        passed += 1
        print("  PASS: \(message)")
    } else {
        failed += 1
        print("  FAIL: \(message) — expected \(b), got \(a) (at line \(line))")
    }
}

// ============================================================
// Setup: use a temp directory to avoid polluting real config
// ============================================================

let tempDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("voice-dictation-test-\(ProcessInfo.processInfo.processIdentifier)")
let vocabFile = tempDir.appendingPathComponent("vocabulary.json")

func cleanup() {
    try? FileManager.default.removeItem(at: tempDir)
}

// Clean up on exit
atexit { cleanup() }

try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

// ============================================================
// Test 1: Default vocabulary file creation and parsing
// ============================================================

print("\n--- Test 1: JSON encoding/decoding ---")

let defaultVocab = Vocabulary(
    recognitionWords: ["Claude Code", "Anthropic"],
    replacements: ["Cloud": "Claude"]
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let data = try encoder.encode(defaultVocab)
try data.write(to: vocabFile, options: .atomic)

let readData = try Data(contentsOf: vocabFile)
let decoded = try JSONDecoder().decode(Vocabulary.self, from: readData)

assertEqual(decoded.recognitionWords.count, 2, "has 2 recognition words")
assert(decoded.recognitionWords.contains("Claude Code"), "contains 'Claude Code'")
assert(decoded.recognitionWords.contains("Anthropic"), "contains 'Anthropic'")
assertEqual(decoded.replacements["Cloud"], "Claude", "Cloud → Claude mapping")

// ============================================================
// Test 2: Prompt building with recognition words
// ============================================================

print("\n--- Test 2: Prompt building (recognition words) ---")

let basePrompt = "你是语音转录的文字清洗助手。"

func buildPrompt(vocab: Vocabulary?) -> String {
    var prompt = basePrompt
    guard let v = vocab else { return prompt }

    if !v.recognitionWords.isEmpty {
        let words = v.recognitionWords.joined(separator: "、")
        prompt += "\n\n以下专有名词必须保持原样：\(words)"
    }

    if !v.replacements.isEmpty {
        let lines = v.replacements.map { "\($0.key) → \($0.value)" }
        prompt += "\n\n以下词语需要替换：\(lines.joined(separator: "、"))"
    }

    return prompt
}

let promptWithVocab = buildPrompt(vocab: decoded)
assert(promptWithVocab.contains("以下专有名词必须保持原样"), "prompt contains recognition instruction")
assert(promptWithVocab.contains("Claude Code"), "prompt contains Claude Code")
assert(promptWithVocab.contains("Anthropic"), "prompt contains Anthropic")
assert(promptWithVocab.contains("以下词语需要替换"), "prompt contains replacement instruction")
assert(promptWithVocab.contains("Cloud → Claude"), "prompt contains Cloud → Claude")

// ============================================================
// Test 3: Prompt building without vocabulary (nil)
// ============================================================

print("\n--- Test 3: Prompt building (no vocabulary) ---")

let promptWithoutVocab = buildPrompt(vocab: nil)
assertEqual(promptWithoutVocab, basePrompt, "nil vocabulary returns base prompt only")

// ============================================================
// Test 4: Prompt building with empty vocabulary
// ============================================================

print("\n--- Test 4: Prompt building (empty vocabulary) ---")

let promptEmpty = buildPrompt(vocab: .empty)
assertEqual(promptEmpty, basePrompt, "empty vocabulary returns base prompt only")

// ============================================================
// Test 5: File modification and re-read
// ============================================================

print("\n--- Test 5: File modification and re-read ---")

var modified = decoded
modified.recognitionWords.append("顾权")
modified.replacements["CC"] = "Claude Code"

let modEncoder = JSONEncoder()
modEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let modData = try modEncoder.encode(modified)
try modData.write(to: vocabFile, options: .atomic)

let reReadData = try Data(contentsOf: vocabFile)
let reDecoded = try JSONDecoder().decode(Vocabulary.self, from: reReadData)

assertEqual(reDecoded.recognitionWords.count, 3, "now has 3 recognition words after edit")
assert(reDecoded.recognitionWords.contains("顾权"), "contains added '顾权'")
assertEqual(reDecoded.replacements["CC"], "Claude Code", "CC → Claude Code mapping added")

let promptAfterEdit = buildPrompt(vocab: reDecoded)
assert(promptAfterEdit.contains("顾权"), "edited prompt contains 顾权")
assert(promptAfterEdit.contains("CC → Claude Code"), "edited prompt contains CC → Claude Code")

// ============================================================
// Test 6: Replacement mapping verification — the core use case
// "我今天在用 Cloud Code" should have Cloud → Claude in prompt
// ============================================================

print("\n--- Test 6: Replacement mapping prompt injection ---")

let testVocab = Vocabulary(
    recognitionWords: [],
    replacements: ["Cloud": "Claude"]
)
let testPrompt = buildPrompt(vocab: testVocab)
assert(!testPrompt.contains("以下专有名词必须保持原样"), "no recognition words section when empty")
assert(testPrompt.contains("以下词语需要替换：Cloud → Claude"), "contains replacement instruction for Cloud → Claude")

// ============================================================
// Test 7: Malformed JSON handling
// ============================================================

print("\n--- Test 7: Malformed JSON handling ---")

let badJSON = "{ not valid json }".data(using: .utf8)!
try badJSON.write(to: vocabFile)

var parseFailed = false
do {
    let _ = try JSONDecoder().decode(Vocabulary.self, from: try Data(contentsOf: vocabFile))
} catch {
    parseFailed = true
}
assert(parseFailed, "malformed JSON correctly fails to parse")

// ============================================================
// Summary
// ============================================================

print("\n===========================")
print("Results: \(passed) passed, \(failed) failed")
print("===========================")

if failed > 0 {
    exit(1)
}
