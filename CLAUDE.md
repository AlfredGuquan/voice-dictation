# Voice Dictation

Mac 语音输入法——按热键说话，干净文字注入光标处。Swift/SwiftUI + SPM。

## 文档索引

| 文档 | 内容 |
|---|---|
| `ARCHITECTURE.md` | 数据流、模块职责、架构决策 |
| `PRD.md` | 功能需求（F1-F4）、tracer findings、验收标准 |
| `status.md` | 工作状态 |
| `specs/design/mockup.html` | 已确认的 UI mockup（暖色 Anthropic 风格） |

## 项目结构

- `Sources/VoiceDictation/` — 全部源码（20 个 Swift 文件）
- `ai_review/user_stories/` — 验收 story YAML
- `specs/design/` — UI 设计稿
- `tracer/` — tracer bullet 实验代码（仅参考，不编译）
- `Tests/` — 独立测试脚本

## 命令

| Command | What it does |
|---|---|
| `swift build` | 编译（产出 .build/debug/VoiceDictation） |
| `.build/debug/VoiceDictation` | 运行应用 |
| `swift Tests/test_history_store.swift` | 运行历史记录测试 |
| `swift Tests/test_vocabulary_integration.swift` | 运行词库测试 |

## Git 规范

Commit 用 conventional commits。Branch 命名 `feat/xxx`、`fix/xxx`。
无 remote，本地开发。

## 运行时依赖

- macOS 13+
- 权限：辅助功能 + 麦克风 + 输入监控（授予终端应用）
- `OPENAI_API_KEY` 环境变量（从 `.env` 或 `~/.voice-dictation/.env` 加载）

<important if="modifying hotkey or text injection logic">
- 全局热键用 CGEvent tap（keyCode 61 = 右 Option），修饰键精确匹配（不用 .contains）
- 文字注入只能用剪贴板粘贴法（Cmd+V），CGEvent 逐字符对 CJK 有编码问题
- 剪贴板操作顺序：检查焦点 → 保存剪贴板 → 写入 → 粘贴 → 等 250ms → 恢复
- passUnretained 用于事件透传，passRetained 会泄漏
</important>

<important if="modifying the floating pill panel">
- NSPanel 必须设 hidesOnDeactivate = false（accessory app 不激活，默认会隐藏）
- canBecomeKey 必须返回 false（不抢焦点）
- create() 返回 optional（无屏幕时不崩溃）
</important>

<important if="modifying notification logic">
- osascript 字符串必须转义引号和反斜杠，防止注入
</important>
