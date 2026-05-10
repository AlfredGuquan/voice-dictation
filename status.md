## Blocker

(none)

## In Progress

- ASR 选型 round 2 -- round 1 已完成对照框架和 4 个 engine 的实测（eval/EXPERIMENT-LOG.md）。Judge 定向：SenseVoice 主推、Whisper 作英文 fallback、Qwen3-ASR MLX 淘汰。但 sherpa-onnx 跑的是 ASLP 粤语特化变体（WSYue-ASR），非原版，需换 2024-07-17 int8 原版重测才公平；同时想测 WhisperKit（Swift Package 零摩擦）和 Apple SpeechAnalyzer（需 macOS 26）。round 2 完成才能决策生产换哪个。执行入口 eval/EXPERIMENT-LOG.md §6 Playbook [2026-04-18]

## Pending

- 生产 ASR 集成路径待决 -- round 2 选型定型后决定 Python↔Swift 桥 / sherpa-onnx Swift binding / localhost HTTP，三条路的 DX 和运行时代价不同 [2026-04-18]
- 选型指标方法论 -- 本轮确认 jiwer CER 归一化（剥标点/大小写/繁简）会抹掉 Whisper 最致命的缺陷，和 LLM judge 结论反转。未来换模型不再以机械 CER 为主指标，以 Judge + 人工 spot-check 为主、latency 作硬约束 [2026-04-18]
- 无焦点通知改为应用内通知 -- 当前用 osascript display notification（macOS 系统通知中心），考虑换成更轻量的应用内 toast 或 pill 内提示 [2026-04-13 QA]
- 药丸背景有方框虚线 -- 浮动药丸 NSPanel 边框渲染异常，需要检查 borderless mask 和背景绘制 [2026-04-13 QA]
- Cmd+, 打开文本框而非主窗口 -- 菜单栏快捷键映射可能被系统或其他应用拦截，需排查 AppDelegate 的 keyEquivalent 绑定 [2026-04-13 QA]
- 对比视图缺少 diff 标记 -- mockup 设计了填充词红色删除线高亮，当前实现只做了纯文本并排展示，需要 diff 算法标记被删除的部分 [2026-04-13 QA]
- 考虑 UI 优化交给 designer agent -- SwiftUI 视觉微调（间距、字体、hover、动画）效率低，评估是否用 designer agent 一次性打磨
- 听写快捷键可配置 -- 当前右 Option 硬编码在 HotkeyManager，改为 Settings 页面可自定义快捷键（录制+保存+HotkeyManager 热加载）
- API Key 修改后需重启 -- Settings 页面保存 API key 后未热加载，应在 UI 标注或实现热加载

## Completed

- F15: 失败重试入口 -- ASR/cleanup 失败后可从 toast 上的『重试』按钮（直接注入光标）或主窗口历史记录失败卡片的『重试』按钮（复制到剪贴板）重新跑一次。重试成功后历史记录从 failed 升级为 success（cleanedText 填充、audioFilePath 清空、wav 删除），失败保持 failed 可继续重试。新增 HistoryStore.updateRecord、DictationPipeline.retry(record:output:)、ToastView/ToastManager 重试按钮。Tests/test_history_retry.swift 16 个测试通过；端到端 QA 验证 history 路径（剪贴板写入 + 卡片升级 + audio 清理）和 toast 路径（toast AX 含重试按钮，retry 触发 ASR + inject fallback 到剪贴板）。stories 在 ai_review/user_stories/f15-failure-retry.yaml [2026-05-10]
- ASR 选型 round 1 -- 新建 eval/ 离线评估框架：录音 recorder（40 条分层脚本照稿念读）、4 engine 实测（openai_whisper_api / sensevoice FunASR CPU / sensevoice_onnx sherpa-onnx int8 / qwen3_asr_mlx）、LLM-as-judge（Opus 4.7 读 40×3 文本）。Judge 裁决 SenseVoice 18 胜 / Whisper 14 胜 / Qwen3 4 胜（11 条样本），推荐 SenseVoice 主力 + Whisper 英文 fallback。详情和下一轮 playbook 在 eval/EXPERIMENT-LOG.md。commit 59e1c5e [2026-04-18]
- F1+F2: 核心听写管道 + 浮动药丸 -- 热键→录音→ASR→清洗→注入完整链路，药丸 UI 录音/处理两态 [2026-04-13]
- F3: 个人词库 -- VocabularyStore + 文件监听 + LLM prompt 注入，19 个测试通过 [2026-04-13]
- F4: 主窗口与历史记录 -- 侧边栏导航 + 历史列表/搜索 + 对比视图 + 词库管理 UI + 设置，33 个测试通过 [2026-04-13]
- Code Review 修复 -- 2 blocker（AX force-cast + osascript 注入）+ 4 warning（modifier 匹配、retain leak、焦点顺序、fatalError）[2026-04-13]
