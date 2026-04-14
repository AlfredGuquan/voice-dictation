#!/usr/bin/env swift
// LCS-based diff: given original tokens + cleaned tokens, mark tokens
// in original as .unchanged or .removed. Only marks deletions (no additions).
// Run: swift tracer/v03-code/f8_lcs.swift

import Foundation

// --- Tokenizer (copied from f8_tokenize_naive.swift, CJK per-char) ---

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

struct TokenSlice {
    let text: String
    let startOffset: Int  // UTF-16 offset into original for highlighting
    let endOffset: Int
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
            while j < scalars.count, isLatin(scalars[j]) {
                run.unicodeScalars.append(scalars[j])
                j += 1
            }
            let utf16Len = run.utf16.count
            tokens.append(TokenSlice(text: run, startOffset: startUTF16, endOffset: startUTF16 + utf16Len))
            utf16Offset += utf16Len
            i = j
        } else if isDigit(sc) {
            var j = i
            var run = ""
            while j < scalars.count, isDigit(scalars[j]) {
                run.unicodeScalars.append(scalars[j])
                j += 1
            }
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

// --- LCS DP, returns which indices of `a` are in the LCS ---

func lcsMask(a: [String], b: [String]) -> [Bool] {
    let n = a.count, m = b.count
    if n == 0 { return [] }
    if m == 0 { return Array(repeating: false, count: n) }

    var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
    for i in 0..<n {
        for j in 0..<m {
            if a[i] == b[j] {
                dp[i+1][j+1] = dp[i][j] + 1
            } else {
                dp[i+1][j+1] = max(dp[i+1][j], dp[i][j+1])
            }
        }
    }

    var mask = Array(repeating: false, count: n)
    var i = n, j = m
    while i > 0 && j > 0 {
        if a[i-1] == b[j-1] {
            mask[i-1] = true
            i -= 1; j -= 1
        } else if dp[i-1][j] >= dp[i][j-1] {
            i -= 1
        } else {
            j -= 1
        }
    }
    return mask
}

// --- Segment merging: consecutive same-kind tokens form one DiffSegment ---

enum SegKind { case unchanged, removed }
struct DiffSegment {
    let text: String
    let kind: SegKind
    let startOffset: Int
    let endOffset: Int
}

func diff(original: String, cleaned: String) -> [DiffSegment] {
    let origToks = tokenize(original)
    let cleanToks = tokenize(cleaned)
    let mask = lcsMask(a: origToks.map { $0.text }, b: cleanToks.map { $0.text })

    // Walk through original text, emitting segments for both tokens and gaps (spaces/punct).
    // Gaps are always .unchanged (they stay visible in the original display).
    var segments: [DiffSegment] = []
    let utf16 = original.utf16
    var cursor = 0  // UTF-16 offset

    for (idx, tok) in origToks.enumerated() {
        // Emit gap before token (unchanged)
        if cursor < tok.startOffset {
            let startIdx = utf16.index(utf16.startIndex, offsetBy: cursor)
            let endIdx = utf16.index(utf16.startIndex, offsetBy: tok.startOffset)
            if let gap = String(utf16[startIdx..<endIdx]) {
                segments.append(DiffSegment(text: gap, kind: .unchanged,
                                            startOffset: cursor, endOffset: tok.startOffset))
            }
        }
        let kind: SegKind = mask[idx] ? .unchanged : .removed
        segments.append(DiffSegment(text: tok.text, kind: kind,
                                    startOffset: tok.startOffset, endOffset: tok.endOffset))
        cursor = tok.endOffset
    }
    // Trailing gap
    if cursor < utf16.count {
        let startIdx = utf16.index(utf16.startIndex, offsetBy: cursor)
        let endIdx = utf16.endIndex
        if let tail = String(utf16[startIdx..<endIdx]) {
            segments.append(DiffSegment(text: tail, kind: .unchanged,
                                        startOffset: cursor, endOffset: utf16.count))
        }
    }

    // Merge consecutive same-kind segments
    var merged: [DiffSegment] = []
    for seg in segments {
        if let last = merged.last, last.kind == seg.kind {
            merged.removeLast()
            merged.append(DiffSegment(
                text: last.text + seg.text,
                kind: last.kind,
                startOffset: last.startOffset,
                endOffset: seg.endOffset
            ))
        } else {
            merged.append(seg)
        }
    }
    return merged
}

// --- Test cases ---

struct Case {
    let label: String
    let original: String
    let cleaned: String
}

let cases: [Case] = [
    Case(label: "C1 填充词删除",
         original: "嗯，我觉得这个方案其实挺好的",
         cleaned: "我觉得这个方案挺好的"),
    Case(label: "C2 重复词删除",
         original: "我我我觉得这个这个 feature 啊",
         cleaned: "我觉得这个 feature"),
    Case(label: "C3 中英混合",
         original: "嗯 今天那个 meeting 其实挺 good 的",
         cleaned: "今天 meeting 挺 good 的"),
    Case(label: "C4 专有名词保留",
         original: "那个 Claude Code 的那个 prompt 写得挺清楚的",
         cleaned: "Claude Code 的 prompt 写得挺清楚的"),
    Case(label: "C5 连续填充",
         original: "然后呢，就是说那个，我们其实可以考虑一下",
         cleaned: "我们可以考虑一下"),
]

func render(_ segs: [DiffSegment]) -> String {
    segs.map { seg in
        switch seg.kind {
        case .unchanged: return seg.text
        case .removed: return "[~\(seg.text)~]"
        }
    }.joined()
}

for c in cases {
    print("\n[\(c.label)]")
    print("  原文: \(c.original)")
    print("  清洗: \(c.cleaned)")
    let segs = diff(original: c.original, cleaned: c.cleaned)
    print("  diff: \(render(segs))")
    let removed = segs.filter { $0.kind == .removed }.map { $0.text }
    print("  标删: \(removed)")
}
