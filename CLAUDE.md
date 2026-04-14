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

### Learned Constraints

<important if="adding shadows to any NSPanel / layer-backed NSView with rounded corners">
- 必须设置 `layer.shadowPath = CGPath(roundedRect:cornerWidth:cornerHeight:)` 匹配形状，否则 CA 用 layer.bounds 矩形作 shadow caster，在浅色背景下暴露方框 halo
- 不要混用 `view.shadow = NSShadow()` 和 CALayer shadow —— 二者不叠加，前者不生效且与 layer shadow 不同步
- 阴影视觉问题在深色背景下不明显，浅色背景（TextEdit、Finder）下才暴露（见 specs/tracer/v03-findings.md F6）
</important>

<important if="adding keyboard shortcuts that should work when main window is frontmost">
- accessory app 必须设置 `NSApp.mainMenu`，statusItem.menu 的 keyEquivalent 只在菜单 popup 时响应
- 主窗口为前台 + 无 mainMenu 时，按键落到 first responder（NSTextField 等），部分组合键会被输入法或字符面板解释成意外行为
- 推荐方案：建 Application menu + Preferences... item with `keyEquivalent: ","`（见 specs/tracer/v03-findings.md F7）
</important>

<important if="adding hotkey conflict detection for user-configurable shortcuts">
- `Carbon RegisterEventHotKey` **查不到系统级/其它 app 已注册 hotkey**（Cmd+Space / Cmd+Tab 都返回 available）
- 只能用静态黑名单 + "只提示不拦截"策略（黑名单见 specs/tracer/v03-findings.md F9）
</important>

<important if="implementing dual-mode hotkey (hold-to-talk + press-to-toggle)">
- 单一 CGEventTap 用 `mask = (1 << flagsChanged) | (1 << keyDown)` 可同时监听两类事件
- 单修饰键走 flagsChanged（按下/松开通过 `event.flags.intersection(modMask)` 判断）
- 组合键走 keyDown + flags 精确匹配
- 热切换不重建 tap，只更新活动绑定（见 specs/tracer/v03-findings.md F9）
</important>

<important if="adding app-internal floating toast / popup">
- 复用 pill 的 NSPanel 配置（nonactivating + canBecomeKey=false + hidesOnDeactivate=false + .floating + .canJoinAllSpaces）即可在前台为其它 app 时保持可见
- `ignoresMouseEvents = true` 让 toast 非交互，不干扰用户当前操作
- 多 toast 堆叠：单例 Manager + maxStack=4 + 超出淘汰最老（见 specs/tracer/v03-findings.md F5）
</important>
