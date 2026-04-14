#!/usr/bin/env swift
// Naive tokenizer: CJK per-char, ASCII/Latin by whitespace+punctuation, digits grouped.
// Run: swift tracer/v03-code/f8_tokenize_naive.swift
//
// 策略：
//   - CJK 字符每字独立 token（粗粒度，但对 diff "只标删除" 足够——
//     填充词"嗯/啊/那个"即使切成单字，LCS 仍能识别连续删除段并整块高亮）
//   - ASCII 字母/数字连续聚合为一个 token
//   - 空白、标点作为分隔符，不产生 token
//   - 输出保留原文位置（range）以便前端高亮

import Foundation

struct Token {
    let text: String
    let range: Range<String.Index>
    let kind: Kind
    enum Kind { case cjk, latin, digit, punct }
}

func isCJK(_ s: Unicode.Scalar) -> Bool {
    // CJK Unified Ideographs (basic + extensions), Hiragana, Katakana, Hangul
    switch s.value {
    case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0x20000...0x2A6DF,
         0x3040...0x309F, 0x30A0...0x30FF,
         0xAC00...0xD7AF:
        return true
    default:
        return false
    }
}

func isLatin(_ s: Unicode.Scalar) -> Bool {
    return (s.value >= 0x41 && s.value <= 0x5A) ||
           (s.value >= 0x61 && s.value <= 0x7A) ||
           s.value == 0x2D  // '-' inside words like state-of-the-art
}

func isDigit(_ s: Unicode.Scalar) -> Bool {
    return s.value >= 0x30 && s.value <= 0x39
}

func tokenize(_ text: String) -> [Token] {
    var tokens: [Token] = []
    var i = text.startIndex
    while i < text.endIndex {
        let ch = text[i]
        let scalar = ch.unicodeScalars.first!

        if isCJK(scalar) {
            // CJK: one char = one token
            let next = text.index(after: i)
            tokens.append(Token(text: String(ch), range: i..<next, kind: .cjk))
            i = next
        } else if isLatin(scalar) {
            // Latin: consume run
            let start = i
            var j = i
            while j < text.endIndex,
                  let sc = text[j].unicodeScalars.first,
                  isLatin(sc) {
                j = text.index(after: j)
            }
            tokens.append(Token(text: String(text[start..<j]), range: start..<j, kind: .latin))
            i = j
        } else if isDigit(scalar) {
            let start = i
            var j = i
            while j < text.endIndex,
                  let sc = text[j].unicodeScalars.first,
                  isDigit(sc) {
                j = text.index(after: j)
            }
            tokens.append(Token(text: String(text[start..<j]), range: start..<j, kind: .digit))
            i = j
        } else {
            // whitespace / punctuation — skip (not emitted as tokens for diff purposes)
            i = text.index(after: i)
        }
    }
    return tokens
}

let samples: [(String, String)] = [
    ("S1 纯中文填充词", "嗯，我觉得这个方案其实挺好的，就是那个预算有点紧"),
    ("S2 中英混合", "嗯 今天那个 meeting 其实挺 good 的"),
    ("S3 专有名词", "Claude Code 的那个 prompt 写得挺清楚的"),
    ("S4 重复词", "我我我觉得这个这个 feature 啊"),
    ("S5 数字单位", "这个需要大概 300 毫秒的延迟"),
    ("S6 标点混合", "对对对，就是 API 的 endpoint，嗯，需要改一下"),
    ("S7 英文为主", "The quick brown fox jumps over"),
    ("S8 长句连续填充", "然后呢，就是说那个，我们其实可以考虑一下"),
    ("S9 技术术语", "React 的 useEffect hook 其实挺好用的"),
    ("S10 引号括号", "他说「嗯，这个 bug 其实挺 tricky 的」"),
    ("S11 连字符英文", "state-of-the-art 模型"),
    ("S12 缩写", "CC 就是 Claude Code 的缩写"),
]

for (label, s) in samples {
    let toks = tokenize(s).map { $0.text }
    print("\n[\(label)]")
    print("  原文: \(s)")
    print("  tokens(\(toks.count)): \(toks)")
}
