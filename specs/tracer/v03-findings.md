# v0.3 Tracer Findings — GUI 层

4 个集成点全部验证完成。独立 SwiftPM demo + 最小 swift script，未启动完整 VoiceDictation app。

| 集成点 | 状态 | 核心结论 |
|---|---|---|
| F5 toast 可行性 | ✅ | NSPanel + nonactivating + floating + canJoinAllSpaces + ignoresMouseEvents=true 工作正常；前台为 TextEdit 时 toast 仍可见 |
| F6 pill 边框根因 | ✅ | 定位为 `rootView.layer.shadowPath` 未设置 → CA 用 layer bounds (矩形) 作 shadow caster；修复 = 指定 roundedRect shadowPath |
| F7 Cmd+, bug 根因 | ✅ | app 未设置 `NSApp.mainMenu`，statusItem.menu 的 keyEquivalent 仅在 menu 打开时响应；Cmd+, 落到 first responder |
| F9 CGEventTap 双模式 | ✅ | 单 tap 同时 mask flagsChanged\|keyDown 工作正常；Carbon RegisterEventHotKey **查不到系统/第三方冲突**，只能走静态黑名单 |

---

## F5: toast 可行性

### 状态: ✅

### 证据
- demo: `tracer/v03-gui/F5-toast/demo.swift`（独立 swift script，可直接 `swift <path>` 跑）
- 截图: `/tmp/f5-toast-with-textedit.png` — TextEdit 全屏白窗口在前，4 个 toast 悬浮在屏幕底部清晰可见
- log:
  ```
  [toast] shown 'Pipeline error: network timeout' at stack idx 0 — total=1
  [toast] shown 'No focused text field — copied to clipboard' at stack idx 1 — total=2
  [toast] shown 'Audio archived — retry later' at stack idx 2 — total=3
  [toast] shown 'Dictation injected' at stack idx 3 — total=4
  [toast] shown 'Recording failed to start' at stack idx 3 — total=4   ← 超过 maxStack=4 时淘汰最老
  ```

### 推荐方案

**NSPanel 配置**（与生产 pill 完全一致，直接复用）：
```swift
let panel = ToastPanel(
    contentRect: ...,
    styleMask: [.nonactivatingPanel, .borderless],
    backing: .buffered, defer: false
)
panel.level = .floating
panel.isFloatingPanel = true
panel.hidesOnDeactivate = false           // ← 必须，accessory app 不激活
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = true
panel.ignoresMouseEvents = true           // ← toast 非交互
panel.animationBehavior = .utilityWindow
```

**动画**：用 `NSAnimationContext.runAnimationGroup` 足矣，不需要 Core Animation。slide-in 从目标位置右侧 40pt 移入 + fade，duration 0.25s easeOut。fade-out 0.2s easeIn，`completionHandler` 中 `orderOut(nil)`。

**Timer 调度**：`Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false)`。entry 对象持有 timer 引用，dismiss 前 `invalidate()` 防止 dangling 触发。

**堆叠策略**（已验证）：
- 垂直堆叠，最老在下方（靠近 pill），新 toast 压到栈顶
- `maxStack = 4`，超过时淘汰最老（fade-out）
- `spacing = 8`，`bottomMargin = 100`（pill 在 +40，留 12pt 视觉间距 + 48 pill 高度）
- dismiss 后剩余 toasts 触发 `relayout()` 动画收紧栈

### 已知坑
- 若加了 `ignoresMouseEvents=true`，后续加"点击 dismiss"需要单独的 overlay panel 或改配置；当前 demo 不支持鼠标交互
- shadow 配置和 pill 一样会踩 F6 坑 → 必须一并设 `shadowPath`（见 F6）

### Phase 3 worker 实现 hint

新文件：`Sources/VoiceDictation/ToastManager.swift`（单例），配合 `Sources/VoiceDictation/ToastPanel.swift`（NSPanel 子类 + ToastViewController）。

- `ToastManager.shared.show(message:level:)` 是唯一入口
- 替换 `DictationPipeline` 中现有 4 个 `showNotification(...)` 调用点（录音启动失败、pipeline 失败带/不带音频存档、无焦点剪贴板 fallback）
- 启动期 2 个场景（缺 API Key、辅助功能权限）**保留 osascript display notification**（tracer 没动这块——与 PRD F5 约束一致）
- 用 `ToastLevel.info/.warning/.error` 对齐 mockup 颜色体系
- 接入 Theme.swift 已有的暖色变量，不要硬编码 RGB

---

## F6: pill 边框根因

### 状态: ✅

### 证据
- demo: `tracer/v03-gui/F6-pill-border/` SPM package（重用生产 `FloatingPillPanel.swift` + `PillViewController.swift`）
- 关键截图对比（亮色 TextEdit 背景下）：
  - `/tmp/f6-prod-light-zoom.png` — **重现问题**，pill 胶囊外侧有矩形"方框"阴影 halo
  - `/tmp/f6-fixed-light-zoom.png` — **修复后**：只剩圆润胶囊阴影，无方框伪影

### 根因

`PillViewController.swift:81-86`：
```swift
view.wantsLayer = true
view.shadow = NSShadow()                       // A: NSShadow API (draws in drawRect)
view.layer?.shadowColor = ...                  // B: CALayer shadow
view.layer?.shadowOffset = CGSize(width: 0, height: -4)
view.layer?.shadowRadius = 24
view.layer?.shadowOpacity = 1
// ← 缺少 view.layer?.shadowPath
```

两个问题：
1. **缺 `shadowPath`**：CALayer 没有 shadowPath 时回退用 `layer.bounds`（280×48 矩形）作为 shadow shape。而 pill 的圆角胶囊是子 view (`container`) 的 `cornerRadius = h/2`，root layer 不知道。结果：矩形 halo 投出，胶囊外侧露出方框轮廓。
2. **混用 NSShadow + CALayer shadow**：`view.shadow = NSShadow()` 创建空 NSShadow（无 color/offset/radius），NSView drawing path 也试图绘制阴影；叠加在 CALayer 阴影上，加重了矩形感。

另外 `container.layer?.masksToBounds = true` 阻止把 shadow 放在 container 自身（会被 clip）——这是为什么阴影被 push 到 root view 上。

### 修复方案（代码级别）

替换 `PillViewController.swift:81-86` 为：

```swift
view.wantsLayer = true
if let layer = view.layer {
    let pillPath = CGPath(roundedRect: view.bounds,
                          cornerWidth: pillHeight / 2,
                          cornerHeight: pillHeight / 2,
                          transform: nil)
    layer.shadowPath = pillPath
    layer.shadowColor = NSColor(white: 0, alpha: 0.15).cgColor
    layer.shadowOffset = CGSize(width: 0, height: -4)
    layer.shadowRadius = 24
    layer.shadowOpacity = 1
}
// NOTE: 删除 view.shadow = NSShadow() — 与 CALayer shadow 重复且不生效
```

### 已知坑
- `view.bounds` 在 `loadView()` 末尾之前可能不稳，确保在 `super.loadView()` + frame 设完之后再算 shadowPath
- view 尺寸变化（F11 进度条不改 pill 尺寸，所以当前没这个问题）需在 `viewDidLayout()` 里同步 shadowPath
- **深色背景（Terminal、Xcode）下方框伪影不明显，浅色背景（TextEdit、Finder、Safari）下才暴露**——这是为什么用户偶尔看到、开发时看不到的原因

### Phase 3 worker 实现 hint

改动仅在 `PillViewController.swift:81-86`，5 行替换。QA 验证：
1. 浅色模式 + 浅色桌面壁纸下，录音时 pill 胶囊外侧无矩形 halo
2. 深色模式下 pill 阴影仍正常显示（shadowOpacity=1 不改）
3. F11 引入新动画时不要重新调 `view.shadow = NSShadow()`

---

## F7: Cmd+, 打开文本框 bug

### 状态: ✅

### 证据
- demo: `tracer/v03-gui/F7-cmd-comma/demo.swift`（独立 swift script）+ `verify.sh`（自动化验证）
- log bug 模式（无 mainMenu）：
  ```
  posted Cmd+,
  --- log ---
  （无 openMain() fired 输出）
  ```
- 截图: `/tmp/f7-bug-after-cmdcomma.png` — 窗口底部仍显示 "Cmd+, action fires: 0 times"

### 根因

生产代码 `main.swift:3-10` + `AppDelegate.swift:27-64`：
1. `NSApp.setActivationPolicy(.accessory)` — 不显示 Dock 和 app 切换条
2. **从未调用 `NSApp.mainMenu = ...`**
3. 唯一菜单是 `statusItem?.menu = menu`（click-to-open popup menu），挂在菜单栏 status icon 上
4. menu item 上的 `keyEquivalent: ","` 只在菜单 **popup 打开时**才响应按键

当用户在主窗口里按 Cmd+, 时：
- 无 mainMenu → system key routing 跳过 menu
- 事件传到 key window 的 first responder（SwiftUI 内某个 NSTextField / field editor）
- NSTextField/NSTextView 的 `keyDown:` 默认不绑 Cmd+,，但某些输入法或 Emoji/Character Viewer hook 会把未绑定的 Cmd-组合键解释为"字符输入面板触发"
- 结果：用户感知是"弹出文本输入框"

### 修复方案（推荐方案 A）

新建 app 主菜单（`AppDelegate.applicationDidFinishLaunching` 里调用）：

```swift
private func setupMainMenu() {
    let mainMenu = NSMenu()

    // Application menu (first item is always the app menu)
    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)
    let appMenu = NSMenu()

    let prefItem = NSMenuItem(
        title: "设置...",
        action: #selector(openSettings),
        keyEquivalent: ","
    )
    prefItem.keyEquivalentModifierMask = [.command]
    prefItem.target = self
    appMenu.addItem(prefItem)

    appMenu.addItem(.separator())
    appMenu.addItem(NSMenuItem(
        title: "退出 Voice Dictation",
        action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"
    ))

    appMenuItem.submenu = appMenu
    NSApp.mainMenu = mainMenu
}

@objc private func openSettings() {
    mainWindowController?.showWindow()
    mainWindowController?.switchToSettingsTab()  // 需新增
}
```

然后在 `MainWindowController` 增加 `switchToSettingsTab()`，让 `MainContentView` 通过 `@Binding selectedSection` 切到 `.settings`。

### 方案 B 备选（更轻）

`NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in ... return nil if Cmd+, }`。但只拦主窗口前台状态，跨窗口一致性差。**推荐 A**。

### 已知坑
- accessory app 加 mainMenu 后，app 在前台时会显示菜单栏——用户未必期望。**可接受**：PRD F7 验收是"按 Cmd+, 打开主窗口并自动切到 Settings tab"，有菜单栏不违反
- 菜单栏显示的是 Application menu（首 item 无 title 会 auto-fill 为 "Voice Dictation" 或进程名）——要明确在 Info.plist/package manifest 设 CFBundleName

### Phase 3 worker 实现 hint

改动 2 处：
1. `AppDelegate.swift` 新增 `setupMainMenu()`（在 `setupStatusItem()` 后调用）+ `@objc openSettings()`
2. `MainWindowController.swift` 新增 `switchToSettingsTab()` 方法（用 Combine `PassthroughSubject` 或 `ObservableObject` 状态传给 SwiftUI）

注意 statusItem menu 里的"打开主窗口"菜单项也保留（用户点击 status icon 仍有入口），但它的 keyEquivalent 可以移除（因为 mainMenu 已接管）。

---

## F9: CGEventTap 双模式

### 状态: ✅

### 证据
- demo: `tracer/v03-gui/F9-hotkey/demo.swift`
- 运行时 log:
  ```
  [F9] dual-mode armed. Press right Option (hold) or Ctrl+Space.
  [F9] synthesizing Ctrl+Space keyDown...
  EVENT: [combo] 49+262144 PRESS        ← keyDown 路径
  [F9] synthesizing right Option down/up...
  EVENT: [single] 61 DOWN                ← flagsChanged 路径 (down)
  EVENT: [single] 61 UP                  ← flagsChanged 路径 (up)
  ```
- 冲突 probe log:
  ```
  Cmd+Space (Spotlight)   → available (OSStatus=0)   ← FALSE POSITIVE
  Ctrl+Space              → available (OSStatus=0)
  Cmd+Shift+D             → available (OSStatus=0)
  Cmd+Shift+5 (screenshot)→ available (OSStatus=0)
  Cmd+Tab (switcher)      → available (OSStatus=0)   ← FALSE POSITIVE
  ```

### 结论

**双模式可行**：单一 CGEventTap 用 `mask = (1 << flagsChanged) | (1 << keyDown)` 可同时监听两种事件类型，回调里 `event.type` 分流到 single-modifier 或 combo 路径。已在 demo 中合成事件验证。

**冲突检测行不通**：`Carbon RegisterEventHotKey` 只能查**当前进程内**已注册的 hotkey，**查不到**：
- 系统级绑定（Spotlight 的 Cmd+Space、switcher 的 Cmd+Tab、screencap 的 Cmd+Shift+5）
- 其它 app 注册的 hotkey（Alfred、Raycast、Hammerspoon 等）
- macOS System Settings → Keyboard Shortcuts 里的用户绑定

AX API（`AXUIElementCreateApplication` 等）也没有"列出全部已注册 hotkey"的 API——这是设计上的隐私边界。

### 推荐方案

**静态黑名单 + 文案提示**：
- 维护一个"已知系统占用"列表（见下方代码），只对匹配的 combo 显示 warning
- UI 文案："此快捷键可能与系统或其它应用冲突，仍可保存"
- 不强制拦截，让用户自行决定（对齐 PRD F9 "只提示不拦截"约束）

### 代码片段（Phase 3 直接用）

**双模式事件 tap**（来源：`tracer/v03-gui/F9-hotkey/demo.swift`，核心逻辑摘录）：

```swift
enum HotkeyMode {
    case singleModifier(keyCode: Int64, modifier: CGEventFlags)  // "hold to talk"
    case combo(keyCode: Int64, modifiers: CGEventFlags)          // "press to toggle"
}

// tapCreate 的 mask 同时包含两类事件
let mask: CGEventMask =
    (1 << CGEventType.flagsChanged.rawValue) |
    (1 << CGEventType.keyDown.rawValue)

// 回调里分流
func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let modMask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
    let pressed = event.flags.intersection(modMask)

    if type == .flagsChanged, case let .singleModifier(target, mod) = activeSingle {
        if keyCode == target {
            // pressed==mod → DOWN; pressed==[] → UP (key released)
            let isDown = (pressed == mod)
            handleSingleTransition(isDown: isDown)
            return nil  // swallow
        }
    }
    if type == .keyDown, case let .combo(target, mods) = activeCombo {
        if keyCode == target && pressed == mods {
            handleComboPress()
            return nil  // swallow
        }
    }
    return Unmanaged.passUnretained(event)
}
```

**静态黑名单**（Phase 3 worker 直接拷贝）：

```swift
struct KnownConflict {
    let keyCode: Int64
    let modifiers: CGEventFlags
    let description: String
}

/// 已知的系统/常用 app hotkey 占用。用于保存前 warning。
/// 不是穷举 — 用户自己的 Alfred/Raycast 绑定查不到，只能 best-effort。
static let knownConflicts: [KnownConflict] = [
    KnownConflict(keyCode: 49, modifiers: [.maskCommand],
                  description: "Spotlight 搜索"),
    KnownConflict(keyCode: 49, modifiers: [.maskCommand, .maskAlternate],
                  description: "Spotlight 访达搜索"),
    KnownConflict(keyCode: 48, modifiers: [.maskCommand],
                  description: "App 切换"),
    KnownConflict(keyCode: 48, modifiers: [.maskCommand, .maskShift],
                  description: "App 反向切换"),
    KnownConflict(keyCode: 0x17, modifiers: [.maskCommand, .maskShift],
                  description: "截图工具栏"),  // Cmd+Shift+5
    KnownConflict(keyCode: 0x14, modifiers: [.maskCommand, .maskShift],
                  description: "截图全屏"),     // Cmd+Shift+3
    KnownConflict(keyCode: 0x15, modifiers: [.maskCommand, .maskShift],
                  description: "截图选区"),     // Cmd+Shift+4
    KnownConflict(keyCode: 49, modifiers: [.maskControl],
                  description: "输入法切换（某些配置）"),  // Ctrl+Space
    KnownConflict(keyCode: 0x63, modifiers: [],
                  description: "macOS 内置听写"),  // F5
    // 右 Option / Fn / CapsLock 单键本身无系统默认占用 — 安全
]

func isKnownConflict(keyCode: Int64, modifiers: CGEventFlags) -> String? {
    knownConflicts.first { $0.keyCode == keyCode && $0.modifiers == modifiers }?.description
}
```

### Phase 3 worker 实现 hint

改动 `HotkeyManager.swift`：
1. 把 `onEvent: ((HotkeyEvent) -> Void)?` 里的 HotkeyEvent 扩展为区分 `.singleModifierDown / .singleModifierUp / .comboPress` 三种，对应 "按住说话" 的 begin/end 和 "toggle" 的 press
2. 加 `var bindings: (single: HotkeyMode?, combo: HotkeyMode?)` 让 SettingsView 热切
3. `DictationPipeline` 消费事件：singleModifierDown → startRecording, singleModifierUp → stopAndProcess, comboPress → toggle(start/stop)
4. 静态黑名单放 `HotkeyManager` 的 `static let knownConflicts: [...]`，SettingsView 保存时调用 `HotkeyManager.isKnownConflict(keyCode:modifiers:)` 展示 warning

**热加载**：`HotkeyManager` 不重建 eventTap（昂贵），只更新 `activeSingle` / `activeCombo` 属性，回调里读最新值即可。

---

## 附录：运行 demos

```bash
# F5 toast (script mode)
swift tracer/v03-gui/F5-toast/demo.swift
# + capture with TextEdit in foreground:
tracer/v03-gui/F5-toast/capture.sh

# F6 pill border (SPM package, uses production code)
cd tracer/v03-gui/F6-pill-border && swift build
# render on light background to expose artifact:
./capture-on-light.sh
# variants: prod | no-nsshadow | shadow-on-container | no-masks-to-bounds | fixed
.build/debug/F6PillDemo fixed

# F7 Cmd+, (script mode)
tracer/v03-gui/F7-cmd-comma/verify.sh bug   # 验证无 mainMenu 时 action 不触发
tracer/v03-gui/F7-cmd-comma/verify.sh fix   # 验证加 mainMenu 后触发（AppleScript 模拟有输入法干扰，CGEvent 直发更可靠）

# F9 hotkey (script mode)
swift tracer/v03-gui/F9-hotkey/demo.swift probe   # Carbon 冲突 probe（证明不可行）
swift tracer/v03-gui/F9-hotkey/demo.swift run     # 双模式 event tap 合成验证
```
