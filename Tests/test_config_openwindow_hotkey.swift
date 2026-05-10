#!/usr/bin/env swift

// Tests the JSON encoding contract for the open-window hotkey persisted in
// UserDefaults. Mirrors HotkeyManager.HotkeyType (Codable enum with two
// cases) — verifies the chord case round-trips, and that an explicit nil
// (the "not configured" state) decodes back to nil.

import Foundation

// ----- Inline mirror of HotkeyManager.HotkeyType -----

enum HotkeyType: Equatable, Codable {
    case singleModifier(keyCode: Int64)
    case chord(keyCode: Int64, modifiers: UInt64)
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

print("=== Open-window hotkey persistence Tests ===\n")

// Test 1: chord round-trips through JSON
print("[Test 1] chord encode/decode round-trip")
do {
    // ⌃⌘V = control + command + V (keyCode 9)
    let mods = (UInt64(0x40000) /* control */) | (UInt64(0x100000) /* command */)
    let original: HotkeyType = .chord(keyCode: 9, modifiers: mods)

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(HotkeyType.self, from: data)

    assert(decoded == original, "chord round-trips equal")
}

// Test 2: optional persistence — nil case
print("\n[Test 2] Optional<HotkeyType> nil round-trip")
do {
    let original: HotkeyType? = nil

    let encoder = JSONEncoder()
    let data = try encoder.encode(original)
    let decoded = try JSONDecoder().decode(HotkeyType?.self, from: data)

    assert(decoded == nil, "nil round-trips as nil")
}

// Test 3: optional persistence — Some(chord) round-trip
print("\n[Test 3] Optional<HotkeyType> Some round-trip")
do {
    let original: HotkeyType? = .chord(keyCode: 4 /* H */, modifiers: 0x100000 | 0x20000 /* cmd+shift */)

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(HotkeyType?.self, from: data)

    assert(decoded == original, "Some(chord) round-trips equal")
}

// Test 4: UserDefaults-style flow — store as Data, read back, decode if present
print("\n[Test 4] UserDefaults Data <-> HotkeyType flow")
do {
    let key = "test.openWindowHotkey"
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: key)

    // Read absent → nil
    var read: HotkeyType? = nil
    if let data = defaults.data(forKey: key),
       let v = try? JSONDecoder().decode(HotkeyType.self, from: data) {
        read = v
    }
    assert(read == nil, "absent key reads as nil")

    // Write
    let toStore: HotkeyType = .chord(keyCode: 9, modifiers: 0x40000 | 0x100000)
    let data = try JSONEncoder().encode(toStore)
    defaults.set(data, forKey: key)

    // Read back
    var read2: HotkeyType? = nil
    if let data = defaults.data(forKey: key),
       let v = try? JSONDecoder().decode(HotkeyType.self, from: data) {
        read2 = v
    }
    assert(read2 == toStore, "stored hotkey reads back equal")

    // Clear
    defaults.removeObject(forKey: key)
    var read3: HotkeyType? = nil
    if let data = defaults.data(forKey: key),
       let v = try? JSONDecoder().decode(HotkeyType.self, from: data) {
        read3 = v
    }
    assert(read3 == nil, "cleared key reads as nil again")
}

// ----- Summary -----

print("\n=== Results: \(passed) passed, \(failed) failed ===")
if failed > 0 {
    exit(1)
}
