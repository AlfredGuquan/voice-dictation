import Foundation

/// Word-level diff between original transcript and cleaned text.
/// Marks tokens in the original that were removed by cleanup (LCS-based).
/// Only emits `.removed` for deletions — additions are not marked.
enum Differ {

    enum SegmentKind {
        case unchanged
        case removed
    }

    struct Segment {
        let text: String
        let kind: SegmentKind
    }

    /// Split text into tokens:
    /// - CJK scalars: one token per character (Chinese tokenizers are unstable, see CLAUDE.md)
    /// - Latin (incl. hyphen): consecutive run
    /// - Digit: consecutive run
    /// - Whitespace/punctuation: skipped (treated as gaps)
    static func tokenize(_ text: String) -> [TokenSlice] {
        var tokens: [TokenSlice] = []
        let scalars = Array(text.unicodeScalars)
        var i = 0
        var utf16Offset = 0
        while i < scalars.count {
            let sc = scalars[i]
            let startUTF16 = utf16Offset
            if isCJK(sc) {
                tokens.append(TokenSlice(
                    text: String(sc),
                    startOffset: startUTF16,
                    endOffset: startUTF16 + Int(sc.utf16.count)
                ))
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
                tokens.append(TokenSlice(
                    text: run,
                    startOffset: startUTF16,
                    endOffset: startUTF16 + utf16Len
                ))
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
                tokens.append(TokenSlice(
                    text: run,
                    startOffset: startUTF16,
                    endOffset: startUTF16 + utf16Len
                ))
                utf16Offset += utf16Len
                i = j
            } else {
                utf16Offset += Int(sc.utf16.count)
                i += 1
            }
        }
        return tokens
    }

    struct TokenSlice {
        let text: String
        let startOffset: Int
        let endOffset: Int
    }

    /// Given original (`a`) and cleaned (`b`) token arrays, return a bool mask
    /// over `a` indicating which tokens are part of the LCS (i.e., preserved).
    /// Comparison is case-insensitive — LLM cleanup often re-capitalizes tokens
    /// (e.g., "claude" -> "Claude"), and we don't want that to mark the original
    /// token as removed. Display still uses the original-case text from `a`.
    static func lcsMask(a: [String], b: [String]) -> [Bool] {
        let n = a.count, m = b.count
        if n == 0 { return [] }
        if m == 0 { return Array(repeating: false, count: n) }

        let aLower = a.map { $0.lowercased() }
        let bLower = b.map { $0.lowercased() }

        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0..<n {
            for j in 0..<m {
                if aLower[i] == bLower[j] {
                    dp[i+1][j+1] = dp[i][j] + 1
                } else {
                    dp[i+1][j+1] = max(dp[i+1][j], dp[i][j+1])
                }
            }
        }

        var mask = Array(repeating: false, count: n)
        var i = n, j = m
        while i > 0 && j > 0 {
            if aLower[i-1] == bLower[j-1] {
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

    /// Produce segments over `original`, where tokens not present in `cleaned`
    /// (per LCS) are marked `.removed`. Gaps (whitespace/punct) stay `.unchanged`.
    /// Adjacent same-kind segments are merged so multi-word deletions render as one block.
    static func diff(original: String, cleaned: String) -> [Segment] {
        let origToks = tokenize(original)
        let cleanToks = tokenize(cleaned)
        let mask = lcsMask(a: origToks.map { $0.text }, b: cleanToks.map { $0.text })

        var segments: [Segment] = []
        let utf16 = original.utf16
        var cursor = 0

        for (idx, tok) in origToks.enumerated() {
            if cursor < tok.startOffset {
                let startIdx = utf16.index(utf16.startIndex, offsetBy: cursor)
                let endIdx = utf16.index(utf16.startIndex, offsetBy: tok.startOffset)
                if let gap = String(utf16[startIdx..<endIdx]) {
                    segments.append(Segment(text: gap, kind: .unchanged))
                }
            }
            let kind: SegmentKind = mask[idx] ? .unchanged : .removed
            segments.append(Segment(text: tok.text, kind: kind))
            cursor = tok.endOffset
        }
        if cursor < utf16.count {
            let startIdx = utf16.index(utf16.startIndex, offsetBy: cursor)
            let endIdx = utf16.endIndex
            if let tail = String(utf16[startIdx..<endIdx]) {
                segments.append(Segment(text: tail, kind: .unchanged))
            }
        }

        var merged: [Segment] = []
        for seg in segments {
            if let last = merged.last, last.kind == seg.kind {
                merged.removeLast()
                merged.append(Segment(text: last.text + seg.text, kind: last.kind))
            } else {
                merged.append(seg)
            }
        }
        return merged
    }

    // MARK: - Scalar class helpers

    private static func isCJK(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0x20000...0x2A6DF,
             0x3040...0x309F, 0x30A0...0x30FF, 0xAC00...0xD7AF:
            return true
        default: return false
        }
    }

    private static func isLatin(_ s: Unicode.Scalar) -> Bool {
        // Basic Latin letters + hyphen, plus Latin-1 Supplement and Latin Extended-A/B
        // so accented tokens like "café", "résumé", "naïve" stay as a single run
        // instead of being split at the accented scalar.
        // Ranges:
        //   A-Z / a-z : 0x41-0x5A / 0x61-0x7A
        //   '-'       : 0x2D
        //   Latin-1 Supplement letters   : 0x00C0-0x00FF
        //   Latin Extended-A             : 0x0100-0x017F
        //   Latin Extended-B             : 0x0180-0x024F
        // (Skip the 0x00D7 multiplication sign and 0x00F7 division sign which
        //  fall inside the Latin-1 letter block.)
        let v = s.value
        if (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A) || v == 0x2D {
            return true
        }
        if v >= 0x00C0 && v <= 0x024F {
            if v == 0x00D7 || v == 0x00F7 { return false }
            return true
        }
        return false
    }

    private static func isDigit(_ s: Unicode.Scalar) -> Bool {
        return s.value >= 0x30 && s.value <= 0x39
    }
}
