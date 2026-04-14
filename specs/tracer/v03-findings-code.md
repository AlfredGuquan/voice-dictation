# v0.3 Tracer Findings — 代码 / 算法层

验证日期：2026-04-14
验证人：tracer-code
验证范围：F8（分词+diff 算法）、F9（HotkeyManager 双模式状态机）、F10（API Key 热加载）
方法：独立 Swift 脚本（`swift <file>.swift`）+ 源码阅读，不启动完整 app。

脚本路径：`tracer/v03-code/`
复现命令：
- `swift tracer/v03-code/f8_tokenize_nl.swift`
- `swift tracer/v03-code/f8_tokenize_naive.swift`
- `swift tracer/v03-code/f8_lcs.swift`
- `swift tracer/v03-code/f9_hotkey_skeleton.swift`

---

## F8: 分词 + LCS

### 推荐

- **分词：自写 Unicode scalar 边界切分（CJK 单字粒度）**。无依赖、行为稳定、对 diff 任务足够好。
- **LCS：自写 O(n×m) DP**（~30 行 Swift）。短文本（≤1000 tokens）下耗时可忽略，不值得引依赖。

### 方案对比

#### 分词

| 方案 | 依赖 | API 简洁度 | 中文切词质量 | 稳定性 | 推荐 |
|------|------|-----------|------------|-------|------|
| Apple `NLTokenizer(.word)` | 系统自带 | 高（Range 回调） | 中（会把"挺好"切成"挺/好"、"就是"切成"就/是"）| **不稳定**（S6 "对对对" 切成 "对/对对"，相同字符不同位置切法不同）| ❌ |
| **自写 Unicode 切分（CJK 单字）** | 无 | 中（30 行代码）| "粗"但可预测 | **完全确定性** | ✅ |
| Jieba-Swift | +SPM 依赖，体积 ~5MB 词表 | 高 | 高（真正词粒度）| 好 | ⚠️ 过度 |

**Jieba-Swift 评估**（未实际安装，基于公开信息）：
- GitHub `yishuihanhan/SwiftJieba` 或 `fxsjy/jieba` 的 Swift port，属社区维护，非 Apple 一等公民
- 带 ~5MB 词典文件，app 体积显著增加
- 对本项目**过度**——目标是 diff 标记删除词，不是 NLP 分析。CJK 单字粒度配合 LCS 合并段已能给出"整块删除高亮"效果

#### 关键实验数据

**NLTokenizer 不稳定示例**（f8_tokenize_nl.swift 输出）：

```
[S6 标点混合] "对对对，就是 API 的 endpoint，嗯，需要改一下"
tokens: ["对", "对对", "就", "是", "API", "的", "endpoint", "嗯", "需要", "改", "一下"]
         ^^^^^^^^^^^  <- "对" 和 "对对" 切法不一致
```

相同的"对"字在不同位置被切成不同长度，这对 diff 是灾难——同一个 token 在原文和清洗后匹配不上。

**自写方案稳定**（f8_tokenize_naive.swift）：所有"对"都切成单字 token，LCS 能干净匹配。

#### LCS + CJK 单字粒度的效果（f8_lcs.swift 输出）

```
[C1 填充词删除]
  原文: 嗯，我觉得这个方案其实挺好的
  清洗: 我觉得这个方案挺好的
  diff: [~嗯~]，我觉得这个方案[~其实~]挺好的      ✅ 填充词被整段标记

[C2 重复词删除]
  原文: 我我我觉得这个这个 feature 啊
  清洗: 我觉得这个 feature
  diff: [~我我~]我觉得[~这个~]这个 feature [~啊~]  ✅ "我我我→我" 识别成删除 2 个

[C5 连续填充]
  原文: 然后呢，就是说那个，我们其实可以考虑一下
  清洗: 我们可以考虑一下
  diff: [~然后呢~]，[~就是说那个~]，我们[~其实~]可以考虑一下  ✅ 连续段合并
```

**关键洞察**：CJK 虽然切到单字，但连续被删除的字通过"合并相邻同类 segment"自动聚合成整段（如"就是说那个"）。所以"单字粒度+段合并"的视觉效果 ≈ "词粒度"，但免去分词歧义。

### Differ.swift 接口签名

```swift
import Foundation

/// 词粒度 diff 结果：原文被拆分成若干连续段，每段要么整段保留、要么整段删除。
/// cleaned 文本不生成 segment——它作为纯文本展示，由调用方自行渲染。
struct DiffSegment: Equatable {
    enum Kind { case unchanged, removed }
    let text: String
    let kind: Kind
    /// UTF-16 offset 到原文的起止，便于 AttributedString / NSAttributedString 定位
    let startOffset: Int
    let endOffset: Int
}

enum Differ {
    /// 计算原文相对清洗后文本的"被删除"标记。
    /// 只输出删除段（.removed）和保留段（.unchanged），不计新增。
    /// - Parameters:
    ///   - original: 原始转录文本
    ///   - cleaned: LLM 清洗后文本
    /// - Returns: 按原文顺序排列的段数组。连续同 kind 的 token 已合并。
    ///            relation: segments.map(\.text).joined() == original
    static func diff(original: String, cleaned: String) -> [DiffSegment]
}
```

不变式（postcondition）：
1. `segments.map(\.text).joined() == original` —— 段拼起来还原原文
2. `segments` 中相邻段 `kind` 不同（已合并）
3. `cleaned` 中每个 token 必定在 `original` 的 `.unchanged` 段内（LCS 保证）
4. 标点/空格始终 `.unchanged`（不 tokenize，作为 gap 保留）

### Phase 3 worker 的实现 hint

- 分词代码完整可复用：`tracer/v03-code/f8_lcs.swift` 的 `tokenize()` + `isCJK/isLatin/isDigit`。直接复制成 `Sources/VoiceDictation/Differ.swift` 即可
- LCS 实现：同文件 `lcsMask()` 函数，30 行，无优化空间也不需要优化（填充词清洗场景 token 数 <200）
- ComparisonView.swift:67 当前是 `Text(record.rawTranscript)` 纯文本，需改为基于 `[DiffSegment]` 渲染 `AttributedString`：
  ```swift
  let segments = Differ.diff(original: record.rawTranscript, cleaned: record.cleanedText)
  var attr = AttributedString()
  for seg in segments {
      var part = AttributedString(seg.text)
      if seg.kind == .removed {
          part.foregroundColor = Theme.diffRemoved  // 对齐 mockup --diff-removed
          part.strikethroughStyle = .single
      }
      attr.append(part)
  }
  Text(attr)
  ```
- `cleanedText` 侧（ComparisonView.swift:91）保持纯文本，不变
- Theme.swift 需补充 `static let diffRemoved: Color` ——从 `specs/design/mockup.html` 的 `--diff-removed` CSS 变量取色

---

## F9 底层: HotkeyManager 状态机

### 状态机图

**pipeline 视角**（与 hotkey type 无关，统一接口）：

```
       ┌──────────────────── cancel ────────────────────┐
       ▼                                                 │
     idle ──pressStart/toggle──▶ recording ──pressEnd/toggle──▶ processing ──done──▶ idle
       ▲                                                                      │
       └──────────────────────────────────────────────────────────────────────┘

  (cancel 在 idle 状态下由 manager 过滤，不透传给 pipeline)
```

**HotkeyManager 内部状态机**（两种模式的事件产生规则）：

```
HotkeyType.singleModifier(keyCode):
  flagsChanged 事件 + keyCode 匹配:
      pressedMods == thisKey → (isDown=false→true) emit .pressStart
      pressedMods != thisKey → (isDown=true→false) emit .pressEnd
  keyDown(Esc) + isActive → emit .cancel

HotkeyType.chord(keyCode, modifiers):
  keyDown 事件 + keyCode 匹配 + flags 精确等于 modifiers:
      emit .toggle
  keyDown(Esc) + isActive → emit .cancel
```

pipeline 把事件映射成状态转移：
- `singleModifier` 模式：`pressStart → startRecording`、`pressEnd → stopAndProcess`
- `chord` 模式：`toggle → if state==idle then startRecording else stopAndProcess`
- 任意模式：`cancel → cancelRecording`

### HotkeyType 枚举

完整代码见 `tracer/v03-code/f9_hotkey_skeleton.swift`，核心：

```swift
enum HotkeyType: Equatable, Codable {
    case singleModifier(keyCode: Int64)
    case chord(keyCode: Int64, modifiers: UInt64)  // modifiers = CGEventFlags.rawValue
}

enum HotkeyEvent {
    case pressStart   // 单修饰键按下 / 组合键按下
    case pressEnd     // 单修饰键松开（仅 singleModifier）
    case toggle       // 组合键切换（仅 chord，语义=一次 tap）
    case cancel       // Esc
}
```

**为什么不用 CGEventFlags 直接存 modifiers？** `CGEventFlags` 在当前 Swift 版本下没标 Codable。用 `UInt64` 存 raw value 最省事，存/读时直接 `CGEventFlags(rawValue:)`。

### 热加载切换方案

**关键洞察**：`CGEvent.tapCreate` 已经同时监听 `flagsChanged + keyDown` 两种事件。两种 HotkeyType 都只用这两种事件的子集——**eventTap 本身不需要重建**。切换只是原子替换 callback 内的分派逻辑所依赖的 `currentHotkey` 字段。

```swift
final class HotkeyManager {
    private(set) var currentHotkey: HotkeyType
    private var isModifierDown = false

    func reload(to newHotkey: HotkeyType) {
        assert(Thread.isMainThread, "reload must be called on main thread")
        guard newHotkey != currentHotkey else { return }

        // 切换瞬间重置"按下"残留，避免旧模式的 isModifierDown=true 被新模式误读
        isModifierDown = false
        currentHotkey = newHotkey
    }
}
```

**不丢事件的保证**：
1. tap 不重建——callback 一直存活，事件不中断
2. `reload` 在主线程串行执行，callback 也 dispatch 到主线程处理，无并发
3. 切换前先 reset `isModifierDown`，旧模式若处于"按住"状态，其 `pressEnd` 被吞；但这是正确行为——用户改热键时当前录音应该被取消（pipeline 层加保护：检测到 reload 发生时若 state==.recording，主动 cancelRecording）

**触发 reload 的路径**：
```
SettingsView 保存新 hotkey
  → 写入 Config（UserDefaults 或 config file）
  → post NotificationCenter.Name("hotkeyDidChange")
  → DictationPipeline 监听该通知 → hotkeyManager.reload(to: newHotkey)
     + 若 state==.recording 则 cancelRecording() 兜底
```

### 冲突检测边界

**能检测**：
| 类别 | 示例 | 检测方式 |
|------|------|---------|
| 系统级保留（可查）| Cmd+Space (Spotlight), Ctrl+Space (输入法), Cmd+Tab (切换), Esc | 静态黑名单硬编码 |
| 本进程已注册 | pipeline 内部冲突 | 遍历自己的 HotkeyType |

**不能检测**：
| 类别 | 示例 | 原因 |
|------|------|------|
| 第三方 app hotkey | Alfred, Raycast, Rectangle, Karabiner | 各 app 私有存储，无公开 API |
| macOS 默认快捷键运行时状态 | 用户关闭了 Spotlight 热键 | `~/Library/Preferences/com.apple.symbolichotkeys.plist` 路径私有 + 格式脆弱，不建议依赖 |
| 浏览器/IDE 内部快捷键 | VS Code, Chrome | 应用本地，API 不可达 |

**建议策略**：
1. 静态黑名单覆盖系统高频冲突（Cmd+Space, Ctrl+Space, Cmd+Tab 等 ~10 项）
2. 第三方常见热键作为"提示"不作为"错误"（如 Option+Space 标注 "Alfred 默认"）
3. Settings UI 文案："以下冲突已知，其它冲突请手动测试"
4. 允许用户保存有冲突的热键（spec 要求"只提示不拦截"）

### Phase 3 worker 的实现 hint

- 可直接基于 `tracer/v03-code/f9_hotkey_skeleton.swift` 扩充，关键是把现有 `HotkeyManager.swift:74-90` 的硬编码分支替换成 `dispatch(type:keyCode:flags:)` 方法
- eventTap 的 mask 已是 `flagsChanged | keyDown`，不需改
- `currentHotkey` 读写都在主线程，不需要 `@Atomic`
- Config 存储建议：`UserDefaults` 存 `HotkeyType` 的 JSON（Codable 已实现），key `"dictationHotkey"`
- Settings 录制控件是另一层（designer + GUI worker 负责），本层只暴露 `HotkeyManager.reload(to:)` 接口
- 冲突检测函数 `detectConflict(_: HotkeyType) -> HotkeyConflict` 可直接复制骨架代码
- **注意**：`HotkeyManager.stop()` 当前不清 `isRightOptionDown`——改名为 `isModifierDown` 并在 stop 时 reset

---

## F10: OpenAIClient 热加载

### 当前结构分析

**没有 OpenAIClient 统一类**。API key 消费分散在两个 service：

| 文件 | 持有方式 | 注入点 |
|------|---------|--------|
| `WhisperService.swift:5` | `private let apiKey: String` | init(apiKey:) |
| `LLMCleanupService.swift:6` | `private let apiKey: String` | init(apiKey:) |
| `DictationPipeline.swift:34-42` | 从 `EnvLoader.load()` 读，一次性注入两个 service | `start()` |

**Settings 侧**（`SettingsView.swift:179-224`）：
- 保存时写文件 `~/.voice-dictation/.env`
- **不通知 pipeline**——pipeline 里的 service 实例仍持旧 key
- 所以要重启 app 才生效

**EnvLoader 搜索顺序**（`EnvLoader.swift:7-15`）：
1. Bundle 相邻 .env（开发）
2. 项目根 .env（`swift run` 时）
3. `~/.voice-dictation/.env`（Settings 写入目标）

### 方案对比

| 维度 | A. 每次读 Config | B. refresh() + Notification |
|------|------------------|-------------------------------|
| 改造范围 | **3 个文件**：WhisperService、LLMCleanupService、DictationPipeline | **4 个文件**：上述 3 个 + SettingsView |
| 改动行数 | ~15 行 | ~30 行 |
| 每次请求开销 | +1 次文件 I/O（`.env` ~几 KB） | 无（仅 Settings 保存时一次 I/O） |
| 复杂度 | 低（无状态同步问题） | 中（需设计 Notification contract） |
| 潜在 bug | 读文件失败的错误路径处理 | 通知错过导致 key 不同步 |
| 测试友好度 | 高（纯函数化） | 中（需模拟 NotificationCenter） |

### 推荐：方案 A（每次从 Config 读）

**理由**：
1. **改造面最小**——service 不再持 key，pipeline 不再注入
2. **无状态同步问题**——没有"Settings 改了但 service 没 refresh"的竞态
3. **开销可忽略**——每次听写最多一次 I/O（`.env` 文件极小，~100B），相比 ASR 网络请求（秒级）可忽略
4. spec F10 约束："不破坏现有调用方——client 接口保持一致"——方案 A 改变 init 签名但不改方法签名，符合约束

**方案 A 改造示意**：

```swift
// 引入一个轻量 Config 抽象
enum Config {
    static var apiKey: String {
        EnvLoader.load()["OPENAI_API_KEY"] ?? ""
    }
}

// WhisperService.swift: 去掉 apiKey 存储，每次读
final class WhisperService {
    // private let apiKey: String  ← 删除
    // init(apiKey: String) { ... }  ← 改为 init() 或去掉

    func transcribe(fileURL: URL) async throws -> TranscriptionResult {
        // ...
        request.setValue("Bearer \(Config.apiKey)", forHTTPHeaderField: "Authorization")
        // ...
    }
}

// LLMCleanupService.swift: 同样改造

// DictationPipeline.swift: start() 简化
func start() {
    // 启动期仍做一次校验
    guard !Config.apiKey.isEmpty else {
        showNotification("...", body: "OPENAI_API_KEY not found...")
        return
    }
    whisperService = WhisperService()
    cleanupService = LLMCleanupService()
    // ...
}
```

**SettingsView.saveApiKey()** 现有逻辑**不需要改**——已经写文件了，下次 Config.apiKey 读的就是新值。

### 改造范围估算

| 文件 | 改动 | 行数 |
|------|------|------|
| `WhisperService.swift` | 删 apiKey 字段、init 参数；transcribe 里改用 Config.apiKey | -3 +2 |
| `LLMCleanupService.swift` | 同上 | -3 +2 |
| `DictationPipeline.swift` | start() 里 service 构造去掉 apiKey 参数 | -2 +0 |
| 新增 `Config.swift` | 包 EnvLoader | +5 |

**总计**：3 个文件修改 + 1 个文件新增，约 ~15 行净增。

### 边界情况

1. **Key 无效**（如 sk-xxx 被删）：`Config.apiKey` 返回空字符串 → request 带 `Bearer `（空） → Whisper API 返回 401 → 按现有 `WhisperError.apiError` 路径反馈（符合 spec F10 验收标准 2）
2. **Settings 正在保存时用户按热键触发听写**：方案 A 下读的是"按热键那一刻"的文件状态，极低概率 race（Settings 保存是原子 write，macOS FileManager 保证）。即使 race 了最多是用到旧 key——不影响功能。
3. **长录音期间 Settings 改 key**：录音结束送 ASR 时读最新 key，用户预期如此——这正是 spec 想要的效果。

### Phase 3 worker 的实现 hint

- 从 `Config.apiKey` 开始——单独一个文件 `Sources/VoiceDictation/Config.swift`，以后扩展其它配置（hotkey、vocabulary 路径）往里加
- 别忘了 `DictationPipeline.start()` 的启动期校验仍要保留——用户首次启动没 key 时给系统通知，和 spec F10 "保存无效 key 后下次转录触发鉴权错误"不冲突
- 不动 SettingsView——它已经把文件写对了
- 测试方式：启动 app 后改 `~/.voice-dictation/.env` 里的 key，不重启，按热键听写，观察请求携带的是新 key（用 Charles 或 Wireshark 抓 HTTPS 麻烦，改用日志：在 WhisperService 里打印 `Config.apiKey.suffix(4)`）

---

## 依赖清单

- 无新 SPM 依赖
- 无系统 API 新依赖（NLTokenizer 已决定不用；CGEvent tap 已在 F1 验证）

## 对 Phase 3 实现的综合建议

1. **执行顺序建议**：F10（最小、无 UI） → F9 底层（单独一层可独立测试） → F8（ComparisonView 改造）。三者互相独立，也可并行
2. **F8 避坑**：不要试图用 NLTokenizer 省 30 行代码。当前实验已证明它对同字符的切法不稳定
3. **F9 避坑**：reload 时一定要 reset 内部 "按下"标志位，否则模式切换后旧状态污染新模式判定
4. **F10 避坑**：保留 `start()` 的启动期校验；去掉 service 内的 apiKey 字段后，所有 `self.apiKey` 引用都要改成 `Config.apiKey`，漏改会编译失败（这是好事）

## 与 tracer-gui 的协调点

- **F8**: worker 只需拿到 `[DiffSegment]` 即可渲染，tracer-gui 可独立调研 AttributedString 高亮方案
- **F9**: 本 tracer 给出底层 reload 接口；tracer-gui 负责 Settings 里的"录制控件"UI（如何展示"按下 Cmd+Shift+D"）。接口契约：UI 层产出 `HotkeyType` 实例 → 存 Config → post Notification → 底层 reload
- **F10**: 纯底层，无 UI 协调需求
