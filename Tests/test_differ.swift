#!/usr/bin/env swift
// Differ unit tests. Keeps the Differ source in sync by embedding a copy of the
// algorithm (standalone swift scripts can't import the app module). If Differ.swift
// changes, mirror the changes here.
//
// Run: swift Tests/test_differ.swift

import Foundation

// -------- copy of Differ algorithm --------

enum SegmentKind { case unchanged, removed }
struct Segment { let text: String; let kind: SegmentKind }
struct TokenSlice { let text: String; let startOffset: Int; let endOffset: Int }

func isCJK(_ s: Unicode.Scalar) -> Bool {
    switch s.value {
    case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0x20000...0x2A6DF,
         0x3040...0x309F, 0x30A0...0x30FF, 0xAC00...0xD7AF:
        return true
    default: return false
    }
}
func isLatin(_ s: Unicode.Scalar) -> Bool {
    return (s.value >= 0x41 && s.value <= 0x5A) ||
           (s.value >= 0x61 && s.value <= 0x7A) ||
           s.value == 0x2D
}
func isDigit(_ s: Unicode.Scalar) -> Bool {
    return s.value >= 0x30 && s.value <= 0x39
}

func tokenize(_ text: String) -> [TokenSlice] {
    var tokens: [TokenSlice] = []
    let scalars = Array(text.unicodeScalars)
    var i = 0
    var utf16Offset = 0
    while i < scalars.count {
        let sc = scalars[i]
        let startUTF16 = utf16Offset
        if isCJK(sc) {
            tokens.append(TokenSlice(text: String(sc), startOffset: startUTF16, endOffset: startUTF16 + Int(sc.utf16.count)))
            utf16Offset += Int(sc.utf16.count)
            i += 1
        } else if isLatin(sc) {
            var j = i
            var run = ""
            while j < scalars.count, isLatin(scalars[j]) { run.unicodeScalars.append(scalars[j]); j += 1 }
            let utf16Len = run.utf16.count
            tokens.append(TokenSlice(text: run, startOffset: startUTF16, endOffset: startUTF16 + utf16Len))
            utf16Offset += utf16Len
            i = j
        } else if isDigit(sc) {
            var j = i
            var run = ""
            while j < scalars.count, isDigit(scalars[j]) { run.unicodeScalars.append(scalars[j]); j += 1 }
            let utf16Len = run.utf16.count
            tokens.append(TokenSlice(text: run, startOffset: startUTF16, endOffset: startUTF16 + utf16Len))
            utf16Offset += utf16Len
            i = j
        } else {
            utf16Offset += Int(sc.utf16.count)
            i += 1
        }
    }
    return tokens
}

func lcsMask(a: [String], b: [String]) -> [Bool] {
    let n = a.count, m = b.count
    if n == 0 { return [] }
    if m == 0 { return Array(repeating: false, count: n) }
    var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
    for i in 0..<n {
        for j in 0..<m {
            if a[i] == b[j] { dp[i+1][j+1] = dp[i][j] + 1 }
            else { dp[i+1][j+1] = max(dp[i+1][j], dp[i][j+1]) }
        }
    }
    var mask = Array(repeating: false, count: n)
    var i = n, j = m
    while i > 0 && j > 0 {
        if a[i-1] == b[j-1] { mask[i-1] = true; i -= 1; j -= 1 }
        else if dp[i-1][j] >= dp[i][j-1] { i -= 1 }
        else { j -= 1 }
    }
    return mask
}

func diff(original: String, cleaned: String) -> [Segment] {
    let origToks = tokenize(original)
    let cleanToks = tokenize(cleaned)
    let mask = lcsMask(a: origToks.map { $0.text }, b: cleanToks.map { $0.text })
    var segments: [Segment] = []
    let utf16 = original.utf16
    var cursor = 0
    for (idx, tok) in origToks.enumerated() {
        if cursor < tok.startOffset {
            let s = utf16.index(utf16.startIndex, offsetBy: cursor)
            let e = utf16.index(utf16.startIndex, offsetBy: tok.startOffset)
            if let gap = String(utf16[s..<e]) {
                segments.append(Segment(text: gap, kind: .unchanged))
            }
        }
        let kind: SegmentKind = mask[idx] ? .unchanged : .removed
        segments.append(Segment(text: tok.text, kind: kind))
        cursor = tok.endOffset
    }
    if cursor < utf16.count {
        let s = utf16.index(utf16.startIndex, offsetBy: cursor)
        if let tail = String(utf16[s..<utf16.endIndex]) {
            segments.append(Segment(text: tail, kind: .unchanged))
        }
    }
    var merged: [Segment] = []
    for seg in segments {
        if let last = merged.last, last.kind == seg.kind {
            merged.removeLast()
            merged.append(Segment(text: last.text + seg.text, kind: last.kind))
        } else { merged.append(seg) }
    }
    return merged
}

// -------- tests --------

var failures = 0

func expect(_ label: String, _ actual: [String], _ expected: [String]) {
    if actual == expected {
        print("  PASS \(label)")
    } else {
        print("  FAIL \(label)")
        print("    expected: \(expected)")
        print("    actual:   \(actual)")
        failures += 1
    }
}

func removedWords(_ segs: [Segment]) -> [String] {
    segs.filter { $0.kind == .removed }.map { $0.text }
}

func concatOriginal(_ segs: [Segment]) -> String {
    segs.map { $0.text }.joined()
}

// C1 填充词删除
do {
    let segs = diff(original: "嗯，我觉得这个方案其实挺好的",
                    cleaned: "我觉得这个方案挺好的")
    expect("C1 removed tokens", removedWords(segs), ["嗯", "其实"])
    if concatOriginal(segs) != "嗯，我觉得这个方案其实挺好的" {
        print("  FAIL C1 reconstruction"); failures += 1
    } else { print("  PASS C1 reconstruction") }
}

// C2 重复词删除
do {
    let segs = diff(original: "我我我觉得这个这个 feature 啊",
                    cleaned: "我觉得这个 feature")
    expect("C2 removed tokens", removedWords(segs), ["我我", "这个", "啊"])
}

// C3 中英混合
do {
    let segs = diff(original: "嗯 今天那个 meeting 其实挺 good 的",
                    cleaned: "今天 meeting 挺 good 的")
    let removed = removedWords(segs)
    // Expect "嗯", "那个", "其实" all marked removed (order preserved).
    expect("C3 removed tokens", removed, ["嗯", "那个", "其实"])
}

// C4 专有名词保留 (Latin run stays intact)
do {
    let segs = diff(original: "那个 Claude Code 的那个 prompt 写得挺清楚的",
                    cleaned: "Claude Code 的 prompt 写得挺清楚的")
    let removed = removedWords(segs)
    // "那个" appears twice in original; only one is in LCS.
    // Algorithm picks the first match greedy; second "那个" gets removed.
    expect("C4 removed tokens", removed, ["那个", "那个"])
    // Make sure "Claude" and "Code" are not individually split/marked
    let hasClaudeRemoved = segs.contains { $0.kind == .removed && $0.text.contains("Claude") }
    if hasClaudeRemoved {
        print("  FAIL C4: Claude unexpectedly marked removed"); failures += 1
    } else { print("  PASS C4: Latin run preserved") }
}

// C5 连续填充 — consecutive deletions merge into one segment
do {
    let segs = diff(original: "然后呢，就是说那个，我们其实可以考虑一下",
                    cleaned: "我们可以考虑一下")
    let removedCount = segs.filter { $0.kind == .removed }.count
    // "然后呢" + "就是说那个" + "其实" — multiple removed segments,
    // but adjacent CJK chars merge into one block per gap boundary.
    if removedCount >= 2 && removedCount <= 4 {
        print("  PASS C5 segment count (\(removedCount))")
    } else {
        print("  FAIL C5 segment count: \(removedCount)"); failures += 1
    }
}

// C6 empty cleaned — all tokens removed
do {
    let segs = diff(original: "嗯啊哦", cleaned: "")
    expect("C6 all removed", removedWords(segs), ["嗯啊哦"])
}

// C7 identical — nothing removed
do {
    let segs = diff(original: "今天天气好", cleaned: "今天天气好")
    expect("C7 nothing removed", removedWords(segs), [])
}

// C8 empty original
do {
    let segs = diff(original: "", cleaned: "something")
    if segs.isEmpty { print("  PASS C8 empty original") }
    else { print("  FAIL C8 empty original"); failures += 1 }
}

if failures == 0 {
    print("\nAll tests passed.")
    exit(0)
} else {
    print("\n\(failures) test(s) failed.")
    exit(1)
}
