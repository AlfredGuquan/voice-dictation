# Model Selection Research (2026-04)

## 研究目标

为 Mac 语音听写应用（Swift/SPM，Apple Silicon M 芯片，中英文混合，单次 2–15 秒短语音，用户走 VPN 网络）选出最优 ASR + LLM 清洗组合，将端到端延迟从当前 7–8 秒压缩到 3 秒内，同时保持中文识别质量。

---

## 方法与信源

- **工具**：WebSearch、WebFetch、HN/Reddit/X 社区搜索（deep-search CLI）
- **时间范围**：优先 2025–2026 数据，2024 及以前数据标注时间
- **语言**：中英文双语搜索
- **信源类型**：官方文档/博客（Deepgram、ElevenLabs、OpenAI、AssemblyAI、Argmax）、独立 benchmark（Artificial Analysis、Soniox 2025 报告、BenchLM.ai）、学术论文（Qwen3-ASR Technical Report 2026-01）、社区讨论（HN、Reddit）

---

## ASR 候选对比

### 总览表

| 候选 | 类型 | 中文支持 | 延迟（短音频） | 中文 WER/CER | 价格 | Swift/SPM 接入 |
|---|---|---|---|---|---|---|
| **OpenAI whisper-1** | 云端 | 是 | 1–2 秒（批处理） | ~18%（Soniox 2025） | $0.006/min | 裸 HTTP |
| **OpenAI gpt-4o-mini-transcribe** | 云端 | 是 | 1.5–2 秒（批处理） | 改善，具体未披露 | $0.003/min | 裸 HTTP / WebSocket |
| **OpenAI gpt-4o-transcribe** | 云端 | 是 | 1.5–2+ 秒（批处理） | WER 4.1%（整体，中文未单独披露） | $0.006/min | 裸 HTTP / WebSocket |
| **Deepgram Nova-3** | 云端 | 是（2026-03 新增） | <300 ms（流式） | 未披露 | $0.0077/min 流式 | 裸 HTTP |
| **ElevenLabs Scribe v2 Realtime** | 云端 | 是 | 150–300 ms（流式） | 93.5% 综合准确率（FLEURS 30 语言）；中文单独 WER 未披露 | $0.0067/min | 裸 HTTP |
| **Fireworks Whisper v3-large** | 云端 | 是 | 300 ms（流式批量 4 秒/小时） | 同 Whisper large-v3 基线 | $0.0032/min 流式 | 裸 HTTP |
| **Groq Whisper large-v3 Turbo** | 云端 | 是 | 理论极快（164–299× RT）；API 调用总延迟含网络 | 同 Whisper large-v3 基线 WER 10.3%（英文） | $0.111/hr | 裸 HTTP |
| **Soniox** | 云端 | 是 | <200 ms 流式 | **6.6% WER**（2025 benchmark，最优之一） | ~$0.10/hr 异步，$0.12/hr 流式 | 裸 HTTP |
| **Speechmatics** | 云端 | 是（Simplified/Traditional） | <1 秒（自称） | 90% 准确率（官方数据，自述） | 用量计费，需询价 | 裸 HTTP |
| **Azure Speech Service** | 云端 | 是（130+ 语言） | 100–300 ms 流式 | 未单独披露中文 | $0.0167/min 实时；$0.006/min 批处理 | SDK 可用 |
| **WhisperKit（argmaxinc）** | 本地 | 是（99 语言） | **~0.46 秒**（M3 Max 实测，streaming latency） | 与 Whisper large-v3 Turbo 同级，WER 2.2%（英文 earnings call） | 一次性，开源 | **原生 Swift SPM** |
| **whisper.cpp + Core ML** | 本地 | 是 | ~0.5–1 秒（small/medium），Core ML 加速 3× | 同 Whisper 基线，medium 模型中文质量较好 | 一次性，开源 | C++ 绑定，有 whisper.spm |
| **Apple SFSpeechRecognizer** | 本地 | 是（20 语言含普通话） | 150–400 ms | 粗估约相当于 Whisper small（无官方数据）；中文质量一般 | 免费，系统内置 | 原生 Swift API |
| **Apple SpeechAnalyzer（macOS 26+）** | 本地 | 是（中文含 AliMeeting 测试 CER ~34%，远场 ~40%） | 实时流式（macOS 26 beta 数据） | 近场 CER 34%（AliMeeting）——中文表现有限 | 免费，系统内置 | 原生 Swift API，但需 macOS 26 |
| **Qwen3-ASR 1.7B（本地 MLX）** | 本地 | **是，专为中文优化** | 1.34 秒均值（AMI+Earnings22，M 芯片 MLX，0.6B 更快） | **WER 4.97%（WenetSpeech）**，远超 Whisper | 一次性，开源 | Python（mlx-qwen3-asr）；Swift 社区项目存在 |
| **Qwen3-ASR API（Alibaba Cloud）** | 云端 | **是，中文专项** | 待测，有 realtime 端点 | 同本地 1.7B 水平 | 按 token 计费，具体需查 | 裸 HTTP（REST/WebSocket） |
| **NVIDIA Parakeet CTC（zh-CN）** | 本地/云端 | **是，普通话+英文 code-switch** | ~80 ms（Apple Silicon，英文版数据） | 未独立公开 CER | 开源权重 | Python/ONNX，无官方 Swift SDK |
| **Google STT（Cloud）** | 云端 | 是 | 流式低延迟 | 54.1% WER（Soniox 2025 benchmark，对比其他服务差距大） | $0.016/min（标准实时） | REST API |

> **数据说明**：Soniox 2025 benchmark（2025 年 3 月，60 语言，YouTube 真实音频）是本表中文 WER 数字的主要独立来源。Google STT WER 54.1% 来自同一 Soniox 报告，远高于其他服务——可能为较老模型版本，建议单独核验。

---

### 各候选详述

#### 1. OpenAI whisper-1（当前方案）
- **质量**：Soniox 2025 benchmark 中文 WER 18%，是主流云端里相对较差的一档
- **延迟**：批处理模型，用户报告 1–2 秒，但属于"发送完整文件→等完整结果"，VPN 额外增加 500 ms–1 秒
- **接入**：裸 HTTP POST `/audio/transcriptions`，Swift 直接用 URLSession 调用
- **成本**：$0.006/min，30 次/天约 $0.027/天

#### 2. OpenAI gpt-4o-mini-transcribe / gpt-4o-transcribe（2025-03 发布）
- **质量**：官方称 WER 全面优于 whisper-1/-2/-3；gpt-4o-transcribe WER 4.1%（整体 benchmark）；gpt-4o-mini-transcribe 更快但略低
- **延迟**：社区反馈批处理模式 1.5–2+ 秒，**未比 whisper-1 更快**；实时流式（WebSocket）延迟更低但接入复杂度高
- **关键问题**：用户反馈从 whisper-1 迁移后有延迟增加、偶发漏字现象（2025 年社区论坛记录）
- **成本**：gpt-4o-mini-transcribe $0.003/min，gpt-4o-transcribe $0.006/min

#### 3. Deepgram Nova-3（2025 年陆续扩展语言，中文 2026-03 新增）
- **质量**：英文 streaming WER 6.84%（54.2% 优于竞品），中文刚加入，准确率尚无独立 benchmark
- **延迟**：流式 <300 ms，业界领先
- **成本**：$0.0077/min 流式，$0.0043/min 批处理
- **中文风险**：2026-03 才正式支持普通话，质量尚未经过充分验证

#### 4. ElevenLabs Scribe v2 Realtime（2025-11 发布）
- **质量**：Artificial Analysis 整体 WER 2.3%（最优），FLEURS 30 语言 93.5% 综合准确率，超越 gpt-4o-mini-transcribe 和 Deepgram Nova-3；中文单独数据未披露
- **延迟**：官方称 30–80 ms 核心处理，端到端 150 ms
- **成本**：$0.0067/min（$0.40/hr），促销后永久定价
- **接入**：REST API，Swift URLSession 即可；无官方 SDK

#### 5. Fireworks AI Whisper v3-large（2025）
- **质量**：与 Whisper large-v3 基线相同；Artificial Analysis 速度排名第一（355.7× RT）
- **延迟**：流式 300 ms；批量 1 小时音频 4 秒处理
- **成本**：$0.0032/min 流式，$0.0009–0.0015/min 批量
- **优势**：最便宜的 Whisper large-v3 云端方案

#### 6. Groq Whisper large-v3 / Turbo
- **速度**：Artificial Analysis benchmark 164–299× RT，理论上 5 秒音频 < 0.03 秒处理
- **延迟**：但 API 调用仍有网络往返；VPN 场景下 RTT 可能 200–500 ms，实际感知延迟受网络制约
- **成本**：$0.111/hr（约 $0.00185/min），无最低消费限制（每次请求最低 10 秒计费）

#### 7. Soniox（2025）
- **质量**：2025 年 Soniox 自发布 benchmark（独立测试需谨慎，属一家之言但方法论公开）中文 WER **6.6%**，明显优于 OpenAI（18%）和 Google（54.1%）
- **延迟**：token-by-token 流式，<200 ms
- **成本**：~$0.10/hr 异步，~$0.12/hr 流式
- **注意**：测试为自家 benchmark，建议项目实测验证

#### 8. WhisperKit（本地，Argmax，Swift 原生）—— **关键推荐**
- **质量**：Whisper large-v3 Turbo 等级，99 语言（含中文）；英文 earnings call WER 2.2%（ICML 2025 论文）；中文与 Whisper large-v3 同级
- **延迟**：**M3 Max 上 0.46 秒流式延迟**（与 Fireworks 并列最快 benchmark）；完全本地，零网络依赖，VPN 不影响
- **接入**：**原生 Swift Package Manager**，一行 `dependencies` 添加即可；支持 macOS 13+
- **成本**：开源免费；模型下载一次（约 800 MB–1.5 GB）
- **重要**：Argmax 已宣布将集成 Apple SpeechAnalyzer（iOS/macOS 26），未来可自动选最优引擎

#### 9. Qwen3-ASR 1.7B（本地 MLX）—— **中文最优本地方案**
- **质量**：WenetSpeech benchmark WER **4.97%**（2026-01 技术报告），显著优于 Whisper large-v3（WenetSpeech 约 7–10%）
- **延迟**：MLX 实现均值 1.34 秒（AMI/Earnings22 测试集，M 芯片），0.6B 版本更快（~0.47 秒）；支持 2 秒 chunk 滚动流式
- **内存**：1.7B FP16 约 3.4 GB；0.6B 版约 1.2 GB
- **接入**：官方仅 Python（`mlx-qwen3-asr`）；有社区 Swift 项目（`qwen3-asr-swift`），成熟度待验证
- **成本**：开源免费

#### 10. NVIDIA Parakeet CTC zh-CN
- **质量**：专为普通话+英文 code-switch 设计，约 600M 参数；偶发重复标点（已知 bug）
- **延迟**：英文 Parakeet TDT ~80 ms（Apple Silicon）；中文 CTC 版本数据未见公开
- **接入**：无 Swift SDK，需通过 Python 或 ONNX 推理；工程接入成本高

#### 11. Apple SFSpeechRecognizer（macOS 15 及以前）
- **质量**：中文质量一般，本地模型能力有限，云端版依赖 Apple 服务器
- **延迟**：150–400 ms（本地模式）
- **优势**：零依赖，无需额外模型文件
- **限制**：中文识别质量不适合生产级听写

#### 12. Apple SpeechAnalyzer（macOS 26+，仅 beta）
- **质量**：AliMeeting 中文 CER 近场 34%、远场 40%——中文质量相当弱
- **现状**：需要 macOS 26 beta，生产不可用
- **结论**：暂不适合本项目

---

## LLM 候选对比

清洗任务特点：输入约 20–80 tokens（ASR 原文），输出约 20–80 tokens（干净文本），附系统 prompt（个人词库约 200 tokens）。关键指标：**TTFT（首 token 延迟）+ 短 prompt 实际响应速度**，而非吞吐量。

### 总览表

| 模型 | TTFT | 输出速度 | 成本（/1M token） | 中文质量 | 指令跟随 | 备注 |
|---|---|---|---|---|---|---|
| **GPT-4o-mini（当前方案）** | ~0.8 秒 | ~100 tok/s | $0.15 in / $0.60 out | 良好 | 优秀 | 稳定可靠 |
| **GPT-4.1-mini** | 0.55–0.90 秒 | 109 tok/s | $0.40 in / $1.60 out | 良好 | 优秀 | 比 4o-mini 贵但能力更强 |
| **Claude Haiku 4.5** | **0.72 秒** | 102 tok/s | $1.00 in / $5.00 out | 优秀 | 优秀 | 中文表现突出，但价格高于 4o-mini |
| **Claude 3.5 Haiku** | 0.70 秒 | 65 tok/s | $0.80 in / $4.00 out | 优秀 | 优秀 | 速度稍慢于 Claude Haiku 4.5 |
| **Gemini 2.5 Flash** | **0.28–0.64 秒** | 192–285 tok/s | $0.30 in / $2.50 out | 优秀 | 优秀 | 目前各指标最均衡；Flash-Lite 更快 |
| **Gemini 2.5 Flash-Lite** | ~0.24–0.56 秒 | ~288–887 tok/s | ~$0.10 in（估算） | 良好 | 良好 | 极速但指令跟随略弱 |
| **Groq Llama 4 Scout** | **0.38 秒** | 460–594 tok/s | $0.11 in / $0.34 out | 良好（多语言支持 12 语言） | 一般（IFBench 39.5%） | 极快但指令跟随弱，不适合精确清洗 |
| **Groq Llama 3.3 70B** | ~0.2–0.5 秒 | 275 tok/s | ~$0.59 in / $0.79 out | 优秀 | 优秀 | 70B 响应质量高，速度也快 |
| **Cerebras Llama 3.1 70B** | ~0.4 秒 | 2100 tok/s | 企业定价 | 良好 | 良好 | 吞吐异常，但 70B 对本任务过重 |
| **本地 Qwen3 8B（MLX）** | <0.5 秒（估算） | 60–120 tok/s（M3/M4） | 免费 | **优秀（母语级）** | 优秀 | 完全本地，VPN 无影响，需额外 ~5 GB 内存 |
| **本地 Qwen3 4B（MLX）** | <0.3 秒（估算） | 100–180 tok/s（M3/M4） | 免费 | 良好 | 良好 | 更轻量，推荐优先测试 |

### 各候选详述

#### GPT-4o-mini（当前方案）
- TTFT ~0.8 秒，全响应约 1–1.5 秒（<200 tokens 输出），稳定
- 指令跟随可靠，不乱改原意
- VPN 场景下加 0.5–1 秒网络延迟

#### GPT-4.1-mini（2025-04 发布）
- TTFT 0.55–0.90 秒，109 tok/s，官方称"比 gpt-4o 降本 83%，延迟减半"
- 指令跟随能力优于 gpt-4o-mini
- 比 gpt-4o-mini 贵 2.7× 但整体能力更强

#### Claude Haiku 4.5
- TTFT 0.72 秒，102 tok/s
- 中文理解深度在同量级模型中最优
- $1/$5 每百万 token，比 GPT-4o-mini 贵约 7 倍，不适合高频小任务

#### Gemini 2.5 Flash
- TTFT **0.28–0.64 秒**，192 tok/s，在主流商用模型中 TTFT 最低
- 中文表现优秀，指令跟随良好
- $0.30/$2.50 每百万 token，定价合理
- Flash-Lite 变体 TTFT 更低（~0.24 秒），但指令跟随可靠性存疑

#### Groq Llama 4 Scout
- TTFT 0.38 秒，输出 460–594 tok/s——纯速度最快
- 但 IFBench 指令跟随得分 39.5%，对"不改原意"这类精确任务风险高
- **不建议**用于清洗任务

#### 本地 Qwen3 系列（MLX）
- Qwen3 8B Q4_K_M 约 5 GB 内存，M3/M4 60–120 tok/s
- Qwen3 4B 约 2.5 GB，速度更快
- 中文能力是 Alibaba 核心优势，专有名词修正效果好
- **完全离线，VPN 零影响**，但需在 LLM 清洗之前先完成模型加载（冷启动需数秒，热启动 <100 ms）

---

## 组合推荐

### 方案 A：极致速度（本地 ASR + 本地 LLM）

**组合**：WhisperKit Large-v3 Turbo（本地）+ Qwen3 4B MLX（本地）

**延迟分解**（估算，M3/M4 Mac）：
| 阶段 | 时间 |
|---|---|
| 录音结束（VAD 检测） | 0 ms（基准） |
| WhisperKit 推理（流式，2–15 秒音频） | 200–600 ms |
| 本地 LLM 调用（Qwen3 4B，~100 tokens 输出） | 300–600 ms |
| 剪贴板写入+粘贴 | ~50 ms |
| **端到端合计** | **~0.5–1.3 秒** |

**VPN 影响**：零影响，全链路本地。

**优点**：
- 离线可用，隐私保护，无 API 成本
- WhisperKit 原生 Swift SPM，接入最简单
- Qwen3 中文清洗质量高

**风险与成本**：
- Qwen3 MLX 接入 Swift 需额外封装（当前无官方 Swift SDK，需通过进程调用或 C 绑定）
- Qwen3 4B 模型首次下载 ~2.5 GB；热启动需保持进程存活
- 在 8 GB 内存 Mac 上同时运行 WhisperKit Large-v3（~1.5 GB）+ Qwen3 4B（~2.5 GB）内存压力较大，建议 16 GB+

**适用用户**：16 GB+ RAM Mac，频繁使用，重视隐私和离线可用性。

---

### 方案 B：质量优先（云端高精度 ASR + 优质 LLM）

**组合**：ElevenLabs Scribe v2 Realtime + Gemini 2.5 Flash

**延迟分解**（估算，有 VPN）：
| 阶段 | 时间 |
|---|---|
| 录音结束 | 0 ms |
| VPN RTT 开销（额外） | +200–500 ms |
| Scribe v2 流式 ASR（含网络） | 300–700 ms |
| Gemini 2.5 Flash LLM 清洗（含网络） | 400–900 ms |
| 剪贴板写入+粘贴 | ~50 ms |
| **端到端合计（含 VPN）** | **~1.0–2.2 秒** |

**VPN 影响**：中等。每次请求额外增加 200–500 ms RTT；VPN 质量好时可控制在 2 秒内。

**优点**：
- Scribe v2 整体 WER 2.3%，目前云端精度最高（含中文 90+ 语言支持）
- Gemini 2.5 Flash TTFT 最低（~0.28 秒），输出速度快
- 两者都是 REST API，Swift URLSession 直接调用

**风险**：
- Scribe v2 中文单独 benchmark 未公开，实际中文质量需实测
- Gemini 和 ElevenLabs 均为非中国服务商，数据出境问题需评估
- VPN 不稳定时延迟跳升，峰值可能超 3 秒

**成本**：每次听写（平均 7 秒音频）约 $0.00047（Scribe）+ $0.00010（Gemini）≈ $0.00057。每天 30 次约 $0.017/天，月费 $0.50。

---

### 方案 C：平衡方案（本地 ASR + 云端 LLM）

**组合**：WhisperKit Large-v3 Turbo（本地）+ GPT-4.1-mini 或 Gemini 2.5 Flash（云端）

**延迟分解**（估算，有 VPN）：
| 阶段 | 时间 |
|---|---|
| 录音结束 | 0 ms |
| WhisperKit 本地推理 | 200–600 ms |
| LLM API 调用（含 VPN RTT） | 700–1400 ms |
| 剪贴板写入+粘贴 | ~50 ms |
| **端到端合计** | **~1.0–2.1 秒** |

**VPN 影响**：仅影响 LLM 清洗阶段（一次网络调用）。ASR 完全离线，因此即使 LLM 调用稍慢，总延迟仍在 2 秒以内。

**优点**：
- WhisperKit 已有成熟 Swift SPM 接入，改动最小（只需替换现有云端 ASR）
- ASR 部分离线，最大风险点（网络不稳定）只剩 LLM 一次调用
- GPT-4.1-mini 与当前 GPT-4o-mini 接口兼容，迁移成本极低
- 若 LLM 调用失败可降级：直接使用 ASR 原文

**与当前方案对比**：
- 当前：whisper-1（云端，1–2 秒）+ GPT-4o-mini（云端，1–1.5 秒）= **两次云端调用，VPN 叠加 ~7–8 秒**
- 方案 C：WhisperKit（本地，0.2–0.6 秒）+ LLM（云端，0.7–1.4 秒）= **一次云端调用，~1–2 秒**

**适用用户**：改动最小的升级路径，优先推荐作为**第一步改造**。

---

## 各方案快速决策矩阵

| 考量 | 方案 A（本地×本地） | 方案 B（云端×云端） | 方案 C（本地 ASR×云端 LLM）|
|---|---|---|---|
| 延迟（有 VPN） | 0.5–1.3 秒 ✅✅ | 1.0–2.2 秒 ✅ | 1.0–2.1 秒 ✅ |
| 中文质量 | 高（Qwen3-ASR 若接入）或中（Whisper）| 待验证（Scribe v2 中文） | 中高（Whisper+GPT） |
| 接入工程量 | 高（Qwen3 MLX Swift 封装待做） | 低（纯 HTTP API） | 低（只换 ASR 部分） |
| VPN 鲁棒性 | 最佳（离线） | 中（两次云调用） | 良好（一次云调用） |
| 成本 | 一次性 | ~$0.5/月 | ~$0.3/月（省去 ASR 费） |
| 推荐优先级 | 中期目标 | 备选（验证 Scribe 中文后） | **立即可做，推荐首选** |

---

## 未解决问题

1. **Scribe v2 中文 CER**：ElevenLabs 未发布中文单独 benchmark，需用实际业务音频（中英混合）实测后再决定是否替换 ASR
2. **Deepgram Nova-3 中文质量**：2026-03 刚加入普通话支持，质量未经社区充分验证
3. **Qwen3-ASR Swift 接入成本**：社区 `qwen3-asr-swift` 项目成熟度不明，生产稳定性需评估；官方只有 Python SDK
4. **VPN 实际 RTT**：用户使用的 veee VPN 对不同服务商（ElevenLabs/Google/OpenAI）的延迟差异未测，方案 B/C 的实际延迟需在真实网络环境下基准测试
5. **本地 LLM 冷启动**：本地 Qwen3 需进程常驻（不能按需启动），需评估后台内存占用对其他应用的影响
6. **Soniox benchmark 独立性**：6.6% WER 数据来自 Soniox 自发布报告（可信度需与其他独立源交叉核验，建议实测）

---

## 信源

- [Deepgram Nova-3 发布博客](https://deepgram.com/learn/introducing-nova-3-speech-to-text-api)
- [Deepgram 扩展 11 种新语言（含中文，2026-03）](https://deepgram.com/learn/deepgram-expands-nova-3-with-11-new-languages-across-europe-and-asia)
- [Deepgram 定价](https://deepgram.com/pricing)
- [ElevenLabs Scribe v2 Realtime 发布博客](https://elevenlabs.io/blog/introducing-scribe-v2-realtime)
- [ElevenLabs Scribe v2 Realtime 150ms 延迟页](https://elevenlabs.io/realtime-speech-to-text)
- [Artificial Analysis STT Benchmark（gpt-4o-transcribe）](https://artificialanalysis.ai/speech-to-text/models/gpt-4o-audio)
- [OpenAI 下一代音频模型发布](https://openai.com/index/introducing-our-next-generation-audio-models/)
- [gpt-4o-transcribe 慢速用户反馈 - Microsoft Q&A](https://learn.microsoft.com/en-us/answers/questions/5785983/gpt-4o-transcribe-for-real-time-speech-to-text-tra)
- [Qwen3-ASR GitHub](https://github.com/QwenLM/Qwen3-ASR)
- [Qwen3-ASR Technical Report (2026-01)](https://arxiv.org/html/2601.21337v1)
- [mlx-qwen3-asr PyPI](https://pypi.org/project/mlx-qwen3-asr/)
- [Qwen3-ASR Swift on Apple Silicon - Medium 博客](https://blog.ivan.digital/qwen3-asr-swift-on-device-asr-tts-for-apple-silicon-architecture-and-benchmarks-27cbf1e4463f)
- [WhisperKit（argmaxinc）GitHub](https://github.com/argmaxinc/WhisperKit)
- [Argmax WhisperKit vs Apple SpeechAnalyzer 博客](https://www.argmaxinc.com/blog/apple-and-argmax)
- [WhisperKit ICML 2025 论文](https://arxiv.org/html/2507.10860v1)
- [Whisper Apple Silicon 各芯片 benchmark](https://www.voicci.com/blog/apple-silicon-whisper-performance.html)
- [Fireworks Whisper 流式 300ms 博客](https://fireworks.ai/blog/streaming-audio-launch)
- [Groq Whisper large-v3 164×/299× benchmark](https://groq.com/blog/groq-runs-whisper-large-v3-at-a-164x-speed-factor-according-to-new-artificial-analysis-benchmark)
- [Soniox vs OpenAI 中文 benchmark](https://soniox.com/compare/soniox-vs-openai/chinese)
- [Soniox 2025 STT benchmark](https://soniox.com/benchmarks)
- [NVIDIA Parakeet CTC zh-CN 模型卡](https://build.nvidia.com/nvidia/parakeet-ctc-0_6b-zh-cn/modelcard)
- [Whisper vs Parakeet vs Apple Speech Engine 对比](https://dicta.to/blog/whisper-vs-parakeet-vs-apple-speech-engine/)
- [Apple SpeechAnalyzer MacStories 实测](https://www.macstories.net/stories/hands-on-how-apples-new-speech-apis-outpace-whisper-for-lightning-fast-transcription/)
- [WWDC 2025 SpeechAnalyzer 介绍](https://dev.to/arshtechpro/wwdc-2025-the-next-evolution-of-speech-to-text-using-speechanalyzer-6lo)
- [Claude Haiku 4.5 API benchmark](https://artificialanalysis.ai/models/claude-4-5-haiku/providers)
- [Gemini 2.5 Flash 性能分析](https://artificialanalysis.ai/models/gemini-2-5-flash)
- [GPT-4.1 mini 性能分析](https://artificialanalysis.ai/models/gpt-4-1-mini)
- [BenchLM LLM 速度排名 2026](https://benchlm.ai/llm-speed)
- [Groq Llama 4 Scout latency](https://www.ailatency.com/models/meta-llama-4-scout.html)
- [Cerebras Inference 速度](https://www.cerebras.ai/blog/cerebras-inference-3x-faster)
- [Open source STT models 2026 benchmark - Northflank](https://northflank.com/blog/best-open-source-speech-to-text-stt-model-in-2026-benchmarks)
