# Architecture — Voice Dictation

Mac 语音输入法：热键触发 → 录音 → 云端 ASR → LLM 清洗 → 焦点注入。

## 数据流

### 听写管道

```
右 Option 热键 (HotkeyManager) → AVAudioEngine 录音 (AudioRecorder)
  → WAV 文件 → OpenAI Whisper API (WhisperService)
  → 原始转录 → GPT-4o-mini 清洗 + 词库注入 (LLMCleanupService)
  → 清洗文字 → 剪贴板粘贴注入 (TextInjector)
  → 历史记录存储 (HistoryStore)
```

DictationPipeline 是编排器，协调以上所有组件并管理状态机（idle → recording → processing → idle）。

### 词库加载

```
~/.voice-dictation/vocabulary.json → VocabularyStore (file watcher)
  → LLMCleanupService system prompt 注入
```

DispatchSource 监听文件变更，热加载。

## 模块地图

### `Sources/VoiceDictation/` — 全部源码

| 文件 | 职责 | 外部依赖 |
|---|---|---|
| main.swift | 入口，accessory app 策略 | AppKit |
| AppDelegate.swift | 菜单栏 status item + 主窗口入口 | AppKit |
| DictationPipeline.swift | 听写状态机编排器 | — |
| HotkeyManager.swift | CGEvent tap 全局热键 | CoreGraphics |
| AudioRecorder.swift | AVAudioEngine 麦克风录音 + RMS 测量 | AVFoundation |
| WhisperService.swift | OpenAI Whisper API 调用 | Foundation (URLSession) |
| LLMCleanupService.swift | GPT-4o-mini 清洗 + 词库 prompt 注入 | Foundation (URLSession) |
| TextInjector.swift | 剪贴板粘贴注入 + 焦点检测 | AppKit, CoreGraphics |
| VocabularyStore.swift | 词库 JSON 持久化 + 文件监听 | Foundation, Dispatch |
| HistoryStore.swift | 历史记录 JSON 持久化 + 搜索 | Foundation, Combine |
| FloatingPillPanel.swift | 非激活 NSPanel 浮动窗口 | AppKit |
| PillViewController.swift | 药丸 UI（波形、进度条、按钮） | AppKit |
| Theme.swift | 设计 token（暖色 Anthropic 调色板） | SwiftUI |
| MainWindowController.swift | NSWindow + NSHostingView 桥接 | AppKit, SwiftUI |
| MainContentView.swift | 侧边栏导航根视图 | SwiftUI |
| HistoryListView.swift | 历史列表 + 搜索 | SwiftUI |
| ComparisonView.swift | 原始/清洗对比视图 | SwiftUI |
| VocabularyView.swift | 词库管理 CRUD UI | SwiftUI |
| SettingsView.swift | 设置页面 | SwiftUI |
| EnvLoader.swift | .env 文件解析器 | Foundation |

## 层级规则

- SwiftUI 视图层只通过 ObservableObject（HistoryStore、VocabularyStore）访问数据，不直接调用 Pipeline
- Pipeline 是唯一写入 HistoryStore 的入口（视图层只读）
- 所有云端 API 调用通过 Service 层（WhisperService、LLMCleanupService），不在其他层直接发请求

## 架构决策

- **SPM 纯命令行构建，不用 Xcode** —— 保持 CI 和 agent 构建的简单性，`swift build` 一条命令完成
- **AppKit NSPanel 而非 SwiftUI overlay** —— NSPanel 是 macOS 唯一能不抢焦点悬浮在其他应用之上的窗口类型
- **剪贴板粘贴注入而非 CGEvent 逐字符** —— CGEvent 对 CJK 字符有编码问题（tracer 验证），剪贴板法可靠但需保存/恢复
- **云端 ASR + LLM 而非本地模型** —— 本地 Whisper 对中英混合识别质量不足（用户实测），云端成本极低（~¥0.0002/次）
- **JSON 文件持久化而非 SQLite** —— 数据量小（历史记录 + 词库），JSON 可读可编辑，无额外依赖

## 跨切面

### API 密钥管理
EnvLoader 从项目根 `.env` 或 `~/.voice-dictation/.env` 加载，启动时一次性读取。密钥变更需重启应用。

### 通知
通过 osascript `display notification` 实现系统通知（无焦点回退、网络错误）。字符串需转义防注入。
