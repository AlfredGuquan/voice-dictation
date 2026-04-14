## Blocker

(none)

## In Progress

(none)

## Pending

- 无焦点通知改为应用内通知 -- 当前用 osascript display notification（macOS 系统通知中心），考虑换成更轻量的应用内 toast 或 pill 内提示 [2026-04-13 QA]
- 药丸背景有方框虚线 -- 浮动药丸 NSPanel 边框渲染异常，需要检查 borderless mask 和背景绘制 [2026-04-13 QA]
- Cmd+, 打开文本框而非主窗口 -- 菜单栏快捷键映射可能被系统或其他应用拦截，需排查 AppDelegate 的 keyEquivalent 绑定 [2026-04-13 QA]
- 对比视图缺少 diff 标记 -- mockup 设计了填充词红色删除线高亮，当前实现只做了纯文本并排展示，需要 diff 算法标记被删除的部分 [2026-04-13 QA]
- 考虑 UI 优化交给 designer agent -- SwiftUI 视觉微调（间距、字体、hover、动画）效率低，评估是否用 designer agent 一次性打磨
- 听写快捷键可配置 -- 当前右 Option 硬编码在 HotkeyManager，改为 Settings 页面可自定义快捷键（录制+保存+HotkeyManager 热加载）
- API Key 修改后需重启 -- Settings 页面保存 API key 后未热加载，应在 UI 标注或实现热加载

## Completed

- F1+F2: 核心听写管道 + 浮动药丸 -- 热键→录音→ASR→清洗→注入完整链路，药丸 UI 录音/处理两态 [2026-04-13]
- F3: 个人词库 -- VocabularyStore + 文件监听 + LLM prompt 注入，19 个测试通过 [2026-04-13]
- F4: 主窗口与历史记录 -- 侧边栏导航 + 历史列表/搜索 + 对比视图 + 词库管理 UI + 设置，33 个测试通过 [2026-04-13]
- Code Review 修复 -- 2 blocker（AX force-cast + osascript 注入）+ 4 warning（modifier 匹配、retain leak、焦点顺序、fatalError）[2026-04-13]
