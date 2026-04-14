# Design Brief — v0.3 打磨批次

**状态**：用户已裁决，实现团队可直接执行
**参考文件**：
- `specs/design/v03-final.html` — 单一方案可视化 + 可交互 demo
- `specs/design/v03-mockup.html` — 候选对比（历史留档）
- `specs/design/mockup.html` — v0.2 基线（tokens 沿用）

## Token 继承

全部沿用 v0.2 暖色 Anthropic palette + DM Sans/Mono 字体。仅以下 token 有修改或新增：

```css
--diff-removed: rgba(196, 101, 58, 0.18);  /* 从 0.10 加深 */
--bg-pill-warm: rgba(255, 252, 247, 0.92); /* 从 0.82 加深 */
--warn:        #B8862E;                     /* 新增 · F9 冲突态 */
--warn-bg:     rgba(184, 134, 46, 0.10);    /* 新增 */
--shadow-pill-soft: 0 6px 20px rgba(60,40,25,0.10), 0 1px 2px rgba(60,40,25,0.04); /* 新增 · 替代 v0.2 的 shadow-pill-warm */
```

## 01 · Pill（F2/F6）

**替换现有 280×40（见 `Sources/VoiceDictation/PillViewController.swift`）为**：

| 属性 | 值 |
|---|---|
| size | 232 × 40 px |
| radius | 22px（非完全胶囊） |
| background | `rgba(255, 252, 247, 0.92)` + `backdrop-blur(24px) saturate(1.2)` |
| border | `1px rgba(0,0,0,0.05)` |
| shadow | `0 6px 20px rgba(60,40,25,0.10), 0 1px 2px rgba(60,40,25,0.04)` |
| padding | `0 5px` |
| button | 30 × 30 · 圆 · icon 13×13 |
| waveform | 10 bars · width 2.5 · gap 2.5 · color `#D97757` |
| progress track | height 2.5 · bg `rgba(0,0,0,0.07)` |

**F6 依赖**：不用 CSS `border` 做描边，改用 `box-shadow`。NSPanel 实现时 `hasShadow = false`，描边通过内部 contentView 的圆角矩形 + shadow 绘制。等 tracer 的 `specs/tracer/v03-findings.md` 确认根因后若有冲突再回调。

## 02 · Toast（F5）

**替换现有 osascript 通知为 app 内 toast**：

| 属性 | 值 |
|---|---|
| 位置 | 屏幕右上，距顶 36px，距右 16px |
| 堆叠 | 纵向向下 · 间距 6px · 上限 3 条 · 溢出排队 |
| 样式 | 深色胶囊灯条 · 单行文本 |
| background | `rgba(40, 30, 22, 0.92)` + `backdrop-blur(12px)` |
| radius | 999px（胶囊） |
| padding | `7px 14px 7px 12px` |
| font | DM Sans 11.5px · `rgba(255,253,250,0.95)` |
| icon | 12×12 · error `#F4A88B` · info `#F0C78E` |

### 触发矩阵（成功路径不吐司）

| 场景 | 类型 | 时长 | 关闭方式 |
|---|---|---|---|
| 网络/API 错误 | error | 3s | 悬停暂停 + 点 ✕ 立即关 |
| 录音异常（超时/磁盘满） | error | 3s | 悬停暂停 + 点 ✕ |
| 剪贴板 fallback（无焦点/CJK 失败） | info | 2s | 不可关闭（瞬态） |
| 权限缺失（麦克风/辅助/输入监控） | persistent | 持续 | 带"打开设置"按钮 |

**动画**：enter `slide-in-right 180ms cubic-bezier(.2,.8,.3,1)` · exit `fade + slide-right 140ms ease-in`

**关键约束**：
- 前台切到其它 app 时仍可见 → panel level 用 `.floating` 或 `.statusBar`
- 悬停暂停倒计时（错误 toast 专属）
- 用户明确反馈：直接注入到焦点框不需要成功 toast（用户自己能看到文字）

## 03 · Diff（F8）

**只改 `--diff-removed` token**：0.10 → 0.18。

| 属性 | 值 |
|---|---|
| 颜色 token | `--diff-removed: rgba(196, 101, 58, 0.18);` |
| 文字颜色 | `var(--cancel)` = `#C4653A` |
| 删除线 | `line-through` · thickness 1.8px |
| 字重 | 500 |
| padding | `1px 4px` |
| radius | 3px |
| line-height | 2.1（避免相邻删除块视觉粘连） |

**范围**：只标红色删除线（原文被清洗的词），不标新增。

## 04 · Hotkey（F9）

Xcode 风紧凑控件。Settings 页现仅此一个 hotkey 字段。

| 属性 | 值 |
|---|---|
| height | 28px |
| padding | `4px 8px` |
| min-width | 140px |
| radius | 6px |
| font | DM Mono 12px |
| kbd chip | 18px 高 · 4px radius · `rgba(0,0,0,0.04)` + border |

### 四态

| 状态 | 视觉 | 文案 |
|---|---|---|
| Default | border `var(--border)` · hover `#D5CCC0` | 显示当前键（如 `right ⌥`） |
| Recording | border `var(--accent)` + glow 3–6px pulse 1.4s | "请按下要录制的键…" |
| Saved | border `var(--confirm)` + glow 3px `var(--confirm-bg)` · 1.2s 后回落 default | 提示"已保存" |
| Conflict | border `var(--warn)` + glow 3px `var(--warn-bg)` | "与系统 Spotlight 冲突 — 本应用将优先响应" |

**交互约束**：
- 支持单修饰键（如 right Option）和组合键（如 `⌃Space`）
- 录制中按 Esc 取消，不修改已保存值
- 冲突只提示不阻断保存（符合功能约束）
- 点清除图标清空（回 default 态）

## 05 · Progress Trickle（F11）

| 阶段 | 进度 | 时长 | 曲线 |
|---|---|---|---|
| 阶段 1 | 0 → 70% | 500ms | `cubic-bezier(.25, .9, .35, 1)` |
| 阶段 2 | 70 → 95% | 2500ms | `cubic-bezier(.3, .7, .4, 1)` |
| 完成 | 95 → 100% | 200ms | linear，之后 pill 淡出 200ms |

### ASR 时长响应

| ASR 实际时长 | 行为 |
|---|---|
| < 500ms | 阶段 1 未结束 → 直接跳 100%（不等补完 70%） |
| 500ms – 3s | 阶段 1 补完后进入阶段 2，ASR 完成时跳 100% |
| > 3s | 阶段 2 渐近到 95% 停住，完成时跳 100% |
| 取消（✕） | fill 淡出 140ms，不跳 100% |

**不变式**：fill 只向右前进不回缩。多次触发 `start()` 也不能让 width 减小。

## 实现优先级建议

1. **P0**：Pill 新尺寸 + toast 基础设施（01 + 02）— 视觉基线
2. **P1**：Diff token 加深（03）— 单行 CSS 变量改动
3. **P1**：Progress trickle（05）— 替换现有进度动画
4. **P2**：Hotkey recorder 四态（04）— Settings 页新控件

## 验证清单

- [ ] Pill 在浅色/暗色桌面都清晰可见（暖色毛玻璃的已知弱点）
- [ ] Toast 在全屏 app 上方可见（panel level 测试）
- [ ] Toast 悬停暂停后移开鼠标继续倒计时
- [ ] Diff 在长文本里相邻删除块不视觉粘连
- [ ] Hotkey 录制中 Esc 不破坏已保存值
- [ ] Trickle 在 < 500ms / 2s / 6s 三档 ASR 下都收尾自然、不回退
