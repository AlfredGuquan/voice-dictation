#!/usr/bin/env swift
// Skeleton design for HotkeyManager supporting both single-modifier "hold-to-talk"
// and chord "toggle" modes, with hot-reload on config change.
// Run: swift tracer/v03-code/f9_hotkey_skeleton.swift
//
// 不包含 CGEvent tap 运行时（会依赖权限+runloop，无法在脚本中 standalone 验证），
// 但枚举/状态/切换逻辑必须编译通过。

import Cocoa
import Carbon.HIToolbox

// MARK: - Public types

enum HotkeyType: Equatable, Codable {
    /// 单修饰键按住说话（flagsChanged 事件驱动）
    /// keyCode 例：61=右 Option, 63=Fn, 57=CapsLock
    case singleModifier(keyCode: Int64)

    /// 组合键 toggle（keyDown 事件驱动）
    /// modifiers 用 CGEventFlags 原始值；keyCode 例：49=Space, 2=D
    case chord(keyCode: Int64, modifiers: UInt64)
}

enum HotkeyEvent {
    case pressStart   // 单修饰键按下 / 组合键按下
    case pressEnd     // 单修饰键松开（仅 singleModifier 触发）
    case toggle       // 组合键切换（仅 chord 触发，语义上等同于 tap）
    case cancel       // Esc
}

// MARK: - State machine

/// 两种模式下的 pipeline 状态（从 pipeline 视角）：
///
///     idle ───pressStart/toggle──▶ recording ──pressEnd/toggle──▶ processing ──done──▶ idle
///      │                             │
///      │                             └──────────cancel───────────▶ idle
///      └──────(cancel 在 idle 被 manager 过滤, 不透传)
///
/// 不同 HotkeyType 下 manager 如何产生事件：
///
/// singleModifier(keyCode):
///     flagsChanged 事件, keyCode 匹配, pressedModifiers == 该键
///         isDown=false → isDown=true,  emit .pressStart
///         isDown=true  → isDown=false, emit .pressEnd
///     Esc keyDown (isActive=true 时): emit .cancel, isDown=false
///
/// chord(keyCode, modifiers):
///     keyDown 事件, keyCode 匹配且 event.flags & modifierMask == modifiers
///         emit .toggle
///     Esc keyDown (isActive=true 时): emit .cancel
///
/// pipeline 侧映射：
///     singleModifier: pressStart → startRecording, pressEnd → stopAndProcess
///     chord: toggle → if idle startRecording else stopAndProcess

final class HotkeyManager {
    var onEvent: ((HotkeyEvent) -> Void)?
    var isActive = false  // pipeline 推回：录音中才拦 Esc

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isModifierDown = false  // 单修饰键模式专用
    private(set) var currentHotkey: HotkeyType

    init(hotkey: HotkeyType) {
        self.currentHotkey = hotkey
    }

    @discardableResult
    func start() -> Bool {
        // 创建 eventTap，callback 里根据 currentHotkey 分派。
        // (实现细节略——本 skeleton 不 runloop，只展示 reload 接口)
        return true
    }

    func stop() {
        // tap disable + runloop remove
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - Hot reload

    /// 热加载新热键。安全性保证：
    /// 1. 串行在主线程切换，无并发
    /// 2. 切换瞬间先把 `isModifierDown = false`，避免旧模式残留"按下"状态
    /// 3. EventTap 本身不重建——它监听 flagsChanged + keyDown 两种事件，
    ///    两种模式都用得到；只是 callback 内的分派逻辑依赖 currentHotkey，
    ///    原子替换 currentHotkey 即可
    /// 4. 如果正在录音（isActive=true），保持 isActive 不动——pipeline 决定是否继续
    func reload(to newHotkey: HotkeyType) {
        assert(Thread.isMainThread, "reload must be called on main thread")
        guard newHotkey != currentHotkey else { return }

        // 模式切换 → 清残留状态
        isModifierDown = false
        currentHotkey = newHotkey

        print("[HotkeyManager] reloaded to \(newHotkey)")
    }

    // MARK: - Event dispatch (pseudo-impl)

    private func dispatch(type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> Bool {
        // Esc 通用处理（两种模式都一样）
        if type == .keyDown && keyCode == 53 && isActive {
            onEvent?(.cancel)
            return true  // swallow
        }

        switch currentHotkey {
        case .singleModifier(let kc):
            guard type == .flagsChanged, keyCode == kc else { return false }
            let mask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
            let pressed = flags.intersection(mask)
            let thisKeyOnly = modifierFlag(for: kc)
            if pressed == thisKeyOnly {
                if !isModifierDown {
                    isModifierDown = true
                    onEvent?(.pressStart)
                }
            } else {
                if isModifierDown {
                    isModifierDown = false
                    onEvent?(.pressEnd)
                }
            }
            return true  // swallow modifier events

        case .chord(let kc, let mods):
            guard type == .keyDown, keyCode == kc else { return false }
            let mask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
            let pressed = flags.intersection(mask)
            if pressed.rawValue == mods {
                onEvent?(.toggle)
                return true  // swallow
            }
            return false
        }
    }

    private func modifierFlag(for keyCode: Int64) -> CGEventFlags {
        switch keyCode {
        case 61, 58: return .maskAlternate  // 右/左 Option
        case 59, 62: return .maskControl     // 左/右 Control
        case 60, 56: return .maskShift       // 右/左 Shift
        case 54, 55: return .maskCommand     // 右/左 Command
        default: return []
        }
    }
}

// MARK: - Conflict detection (静态黑名单 + 可查 API)

enum HotkeyConflict {
    case systemReserved(String)  // "Spotlight"
    case possiblyThirdParty(String)  // "Alfred/Raycast 常用"
    case none
}

/// 只能检测"静态已知"冲突。第三方 app 的 hotkey 无法从公开 API 查到
/// （Carbon `RegisterEventHotKey` 只看到本进程注册的，
/// 系统级 shortcuts 存 `~/Library/Preferences/com.apple.symbolichotkeys.plist`，
/// 路径私有且脆弱）。因此只给黑名单 + "建议手动测试"提示。
func detectConflict(_ hotkey: HotkeyType) -> HotkeyConflict {
    // 系统级黑名单（默认启用时占用）
    let systemChords: [(keyCode: Int64, modifiers: UInt64, name: String)] = [
        (49, CGEventFlags.maskCommand.rawValue, "Spotlight (Cmd+Space)"),
        (49, CGEventFlags.maskControl.rawValue, "Input Source Switch (Ctrl+Space)"),
        (48, CGEventFlags.maskCommand.rawValue, "App Switcher (Cmd+Tab)"),
        (53, 0, "Esc (保留给取消录音)"),
    ]

    // 第三方常见（提示但不拦）
    let thirdPartyChords: [(keyCode: Int64, modifiers: UInt64, name: String)] = [
        (49, CGEventFlags.maskAlternate.rawValue, "Alfred 默认 (Option+Space)"),
        (49, (CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue), "Raycast 默认 (Cmd+Shift+Space)"),
    ]

    if case .chord(let kc, let mods) = hotkey {
        for c in systemChords where c.keyCode == kc && c.modifiers == mods {
            return .systemReserved(c.name)
        }
        for c in thirdPartyChords where c.keyCode == kc && c.modifiers == mods {
            return .possiblyThirdParty(c.name)
        }
    }
    return .none
}

// MARK: - Smoke test (compile-only)

let mgr = HotkeyManager(hotkey: .singleModifier(keyCode: 61))
mgr.reload(to: .chord(keyCode: 49, modifiers: CGEventFlags.maskControl.rawValue))
mgr.reload(to: .singleModifier(keyCode: 63))  // Fn

let conflict1 = detectConflict(.chord(keyCode: 49, modifiers: CGEventFlags.maskCommand.rawValue))
let conflict2 = detectConflict(.singleModifier(keyCode: 61))
print("conflict1:", conflict1)
print("conflict2:", conflict2)

print("\n✅ Compile + basic reload + conflict detection OK")
