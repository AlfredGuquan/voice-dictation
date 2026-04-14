#!/usr/bin/env swift
// Tokenize with Apple NaturalLanguage framework (NLTokenizer .word).
// Run: swift tracer/v03-code/f8_tokenize_nl.swift

import Foundation
import NaturalLanguage

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

func tokenize(_ text: String) -> [String] {
    let tokenizer = NLTokenizer(unit: .word)
    tokenizer.string = text
    var tokens: [String] = []
    tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
        let token = String(text[range])
        if !token.isEmpty { tokens.append(token) }
        return true
    }
    return tokens
}

for (label, s) in samples {
    let toks = tokenize(s)
    print("\n[\(label)]")
    print("  原文: \(s)")
    print("  tokens(\(toks.count)): \(toks)")
}
