#!/usr/bin/env swift
// HotkeyType Codable + conflict-detection unit tests.
// Mirrors the enum from Sources/VoiceDictation/HotkeyManager.swift (standalone
// swift scripts can't import the app module). If HotkeyType changes shape,
// mirror the changes here.
//
// Run: swift Tests/test_hotkey_codable.swift

import Foundation
import Cocoa

// -------- copy of HotkeyType + knownConflicts --------

enum HotkeyType: Equatable, Codable {
    case singleModifier(keyCode: Int64)
    case chord(keyCode: Int64, modifiers: UInt64)
}

struct KnownConflict {
    let keyCode: Int64
    let modifiers: UInt64
    let description: String
}

let knownConflicts: [KnownConflict] = [
    KnownConflict(keyCode: 49, modifiers: CGEventFlags.maskCommand.rawValue,
                  description: "Spotlight 搜索"),
    KnownConflict(keyCode: 48, modifiers: CGEventFlags.maskCommand.rawValue,
                  description: "App 切换"),
]

func conflictDescription(for hotkey: HotkeyType) -> String? {
    switch hotkey {
    case .singleModifier: return nil
    case .chord(let kc, let mods):
        return knownConflicts.first { $0.keyCode == kc && $0.modifiers == mods }?.description
    }
}

// -------- test scaffolding --------

var passed = 0
var failed = 0

func check(_ ok: Bool, _ label: String) {
    if ok { passed += 1; print("  PASS \(label)") }
    else  { failed += 1; print("  FAIL \(label)") }
}

// -------- tests --------

print("[Test 1] Round-trip singleModifier")
do {
    let h = HotkeyType.singleModifier(keyCode: 61)
    let data = try JSONEncoder().encode(h)
    let decoded = try JSONDecoder().decode(HotkeyType.self, from: data)
    check(decoded == h, "singleModifier(61) encode→decode preserves value")
}

print("[Test 2] Round-trip chord with multiple modifiers")
do {
    let mods = CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue
    let h = HotkeyType.chord(keyCode: 49, modifiers: mods)
    let data = try JSONEncoder().encode(h)
    let decoded = try JSONDecoder().decode(HotkeyType.self, from: data)
    check(decoded == h, "chord(49, ⌃⇧) round-trip")
}

print("[Test 3] Round-trip cases are distinct (JSON has enum tag)")
do {
    let a = HotkeyType.singleModifier(keyCode: 49)
    let b = HotkeyType.chord(keyCode: 49, modifiers: 0)
    let encA = try JSONEncoder().encode(a)
    let encB = try JSONEncoder().encode(b)
    let decA = try JSONDecoder().decode(HotkeyType.self, from: encA)
    let decB = try JSONDecoder().decode(HotkeyType.self, from: encB)
    check(decA != decB, "singleModifier(49) and chord(49, 0) don't collide")
    check(decA == a, "decoded singleModifier preserved")
    check(decB == b, "decoded chord preserved")
}

print("[Test 4] Conflict detection hits known system shortcuts")
do {
    let spot = HotkeyType.chord(keyCode: 49, modifiers: CGEventFlags.maskCommand.rawValue)
    check(conflictDescription(for: spot) == "Spotlight 搜索", "Cmd+Space flagged as Spotlight")

    let appSw = HotkeyType.chord(keyCode: 48, modifiers: CGEventFlags.maskCommand.rawValue)
    check(conflictDescription(for: appSw) == "App 切换", "Cmd+Tab flagged as App switcher")
}

print("[Test 5] Non-conflicting chords report nil")
do {
    let rightOpt = HotkeyType.singleModifier(keyCode: 61)
    check(conflictDescription(for: rightOpt) == nil, "right Option has no system conflict")

    let cmdShiftD = HotkeyType.chord(
        keyCode: 2,
        modifiers: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue
    )
    check(conflictDescription(for: cmdShiftD) == nil, "Cmd+Shift+D unflagged")
}

print("[Test 6] Modifier flag mask (intersection semantics)")
do {
    let mask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
    // A flagsChanged event for right Option arrives with .maskAlternate set + capsLock-independent.
    let simulated: CGEventFlags = [.maskAlternate, .maskNonCoalesced]
    let pressed = simulated.intersection(mask)
    check(pressed == .maskAlternate, "intersection strips non-mod bits")
}

print("")
print("=== Results: \(passed) passed, \(failed) failed ===")
if failed > 0 { exit(1) }
