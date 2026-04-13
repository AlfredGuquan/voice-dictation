#!/usr/bin/env swift

// Tests VocabularyStore save/load cycle with the exact data patterns
// that VocabularyView will use (add word, delete word, add/edit/delete replacement).

import Foundation

// Inline model (mirrors VocabularyStore.Vocabulary)
struct Vocabulary: Codable, Equatable {
    var recognitionWords: [String]
    var replacements: [String: String]
    static let empty = Vocabulary(recognitionWords: [], replacements: [:])
}

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

let tempDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("vocab_test_\(Int(Date().timeIntervalSince1970))")
try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
let testFile = tempDir.appendingPathComponent("vocabulary.json")

func save(_ vocab: Vocabulary) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(vocab)
    try data.write(to: testFile, options: .atomic)
}

func load() throws -> Vocabulary {
    let data = try Data(contentsOf: testFile)
    return try JSONDecoder().decode(Vocabulary.self, from: data)
}

print("=== Vocabulary Integration Tests ===\n")

// Test 1: Add recognition word
print("[Test 1] Add recognition word")
do {
    var vocab = Vocabulary.empty
    vocab.recognitionWords.append("Anthropic")
    try save(vocab)
    let loaded = try load()
    assert(loaded.recognitionWords == ["Anthropic"], "word added and persisted")
}

// Test 2: Delete recognition word
print("\n[Test 2] Delete recognition word")
do {
    var vocab = Vocabulary(recognitionWords: ["Claude", "Anthropic", "GPT"], replacements: [:])
    vocab.recognitionWords.removeAll { $0 == "GPT" }
    try save(vocab)
    let loaded = try load()
    assert(loaded.recognitionWords == ["Claude", "Anthropic"], "word deleted")
    assert(!loaded.recognitionWords.contains("GPT"), "GPT removed")
}

// Test 3: Add replacement
print("\n[Test 3] Add replacement")
do {
    var vocab = Vocabulary.empty
    vocab.replacements["CC"] = "Claude Code"
    try save(vocab)
    let loaded = try load()
    assert(loaded.replacements["CC"] == "Claude Code", "replacement added")
}

// Test 4: Edit replacement (change value)
print("\n[Test 4] Edit replacement value")
do {
    var vocab = Vocabulary(recognitionWords: [], replacements: ["CC": "Claude Code"])
    vocab.replacements["CC"] = "Claude Code 2.0"
    try save(vocab)
    let loaded = try load()
    assert(loaded.replacements["CC"] == "Claude Code 2.0", "replacement value updated")
}

// Test 5: Edit replacement (change key)
print("\n[Test 5] Edit replacement key (rename trigger)")
do {
    var vocab = Vocabulary(recognitionWords: [], replacements: ["CC": "Claude Code"])
    // Rename: remove old key, add new key
    vocab.replacements.removeValue(forKey: "CC")
    vocab.replacements["claude code"] = "Claude Code"
    try save(vocab)
    let loaded = try load()
    assert(loaded.replacements["CC"] == nil, "old trigger removed")
    assert(loaded.replacements["claude code"] == "Claude Code", "new trigger set")
}

// Test 6: Delete replacement
print("\n[Test 6] Delete replacement")
do {
    var vocab = Vocabulary(recognitionWords: [], replacements: ["CC": "Claude Code", "GH": "GitHub"])
    vocab.replacements.removeValue(forKey: "CC")
    try save(vocab)
    let loaded = try load()
    assert(loaded.replacements.count == 1, "one replacement remaining")
    assert(loaded.replacements["GH"] == "GitHub", "correct replacement remaining")
}

// Test 7: Mixed operations preserve both sections
print("\n[Test 7] Mixed operations preserve both sections")
do {
    var vocab = Vocabulary(
        recognitionWords: ["Claude", "Anthropic"],
        replacements: ["CC": "Claude Code"]
    )
    vocab.recognitionWords.append("GPT-4o")
    vocab.replacements["GH"] = "GitHub"
    try save(vocab)
    let loaded = try load()
    assert(loaded.recognitionWords.count == 3, "3 recognition words")
    assert(loaded.replacements.count == 2, "2 replacements")
    assert(loaded.recognitionWords.contains("GPT-4o"), "new word present")
    assert(loaded.replacements["GH"] == "GitHub", "new replacement present")
}

// Cleanup
try FileManager.default.removeItem(at: tempDir)

print("\n=== Results: \(passed) passed, \(failed) failed ===")
if failed > 0 { exit(1) }
