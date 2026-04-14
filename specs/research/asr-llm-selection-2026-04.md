# ASR + LLM 模型选型调研 — 2026-04

**背景**：macOS 语音输入法。按热键说话（2-10s）→ ASR 转文字 → LLM 清洗 → 注入光标。  
**目标**：端到端 <3s（理想 2s）。  
**当前痛点**：OpenAI Whisper-1 + GPT-4o-mini 走 VPN，实测 7-8s，大头在网络开销。

---

## 一、推荐组合

### 方案 A：Groq Whisper + Groq Llama（最快云端路径）

| 组件 | 选型 |
|---|---|
| ASR | Groq `whisper-large-v3-turbo` |
| LLM | Groq `llama-3.1-8b-instant` |

**延迟拆解估算（从中国走 VPN 到 Groq Sydney 节点）**

| 步骤 | 估算 |
|---|---|
| 音频录制（含 VAD 停顿检测） | 0.3-0.5s（用户控制） |
| VPN + 网络 RTT（Sydney） | 0.15-0.3s |
| Groq ASR 推理（259x 实时速率，5s 音频） | ~0.02s 推理本身 |
| HTTP 传输开销（上传 ~50-150KB 音频） | 0.1-0.3s |
| Groq ASR 批处理实测 | **0.15-0.32s 端到端** |
| Groq LLM TTFT（Llama 3.1 8B） | ~0.08-0.1s |
| LLM 输出（~30-60 tokens） | ~0.1-0.2s |
| **总估算** | **~1.0-1.8s**（不含录音） |

**macOS 集成难度**：低。REST API，Swift URLSession 即可。无新依赖。

**成本**：Groq Whisper large-v3-turbo $0.04/小时音频，Llama 3.1 8B $0.05/M tokens。日均 50 次 × 5s ≈ 250s 音频 ≈ $0.003/天。

**已知风险**：
- Groq 无中国节点，最近节点为 Sydney（Nov 2025 上线）。走 VPN 的网络路径取决于 VPN 出口地，若出口在美国则 RTT 更高，需实测
- Groq Whisper 不支持流式输出（非 streaming ASR），但 5s 短音频批处理延迟已足够低
- gpt-4o-mini-transcribe 用户反馈语言检测不稳定，中英混合场景下 Groq 走 Whisper large-v3 架构更稳定

---

### 方案 B：WhisperKit（本地 ASR）+ Groq Llama（云端 LLM）

| 组件 | 选型 |
|---|---|
| ASR | WhisperKit `whisper-large-v3-turbo`（CoreML + ANE，本机） |
| LLM | Groq `llama-3.1-8b-instant` |

**延迟拆解估算（M2/M3 Mac）**

| 步骤 | 估算 |
|---|---|
| 音频录制 | 0.3-0.5s |
| WhisperKit 本地推理（5s 音频，ANE 加速） | 0.4-0.6s（论文实测 0.45s 均值） |
| VPN + 网络 RTT（Groq LLM） | 0.15-0.3s |
| Groq LLM TTFT + 输出 | ~0.2-0.35s |
| **总估算** | **~1.1-1.8s**（不含录音） |

**macOS 集成难度**：中。WhisperKit 是原生 Swift Package（MIT 协议），无 C++ 工具链要求，SPM 直接添加。首次运行需下载模型（~800MB），后续本地。

**成本**：ASR 零成本（本地）。LLM 同方案 A。

**已知风险**：
- WhisperKit 在 ICML 2025 论文中对 Chinese 有 2% WER 回归，源于中文训练数据较少；Whisper large-v3 原始中文质量好于其优化变体
- 首次启动需下载模型，离线时 LLM 部分不可用
- WhisperKit 支持 iOS 17+/macOS 14+，当前项目无需系统版本升级

---

### 方案 C：Apple SpeechAnalyzer（本地 ASR）+ Apple Foundation Models（本地 LLM）

| 组件 | 选型 |
|---|---|
| ASR | `SpeechAnalyzer`（macOS 26 Tahoe，系统内置） |
| LLM | `FoundationModels` framework（macOS 26 系统内置 3B 模型） |

**延迟拆解估算**

| 步骤 | 估算 |
|---|---|
| 音频录制 | 0.3-0.5s |
| SpeechAnalyzer 推理（on-device，约 70x 实时速率） | ~0.07s（5s 音频） |
| Foundation Models 推理（3B，ANE） | ~0.3-0.8s（需实测） |
| **总估算** | **<1.5s**（不含录音，理论最优） |

**macOS 集成难度**：最低。纯 Swift 原生 API，无外部依赖，无网络请求。

**成本**：完全免费。无 API Key，无流量计费。

**已知风险**：
- **需要 macOS 26（Tahoe）**，相当于要求用户 2025 年秋之后的 macOS 版本。如果项目要兼容 macOS 13-15，此方案不可用
- SpeechAnalyzer 仅支持 10 种语言（支持中文简体），无自定义词汇、无说话人识别
- Argmax 实测 SpeechAnalyzer 错误率 14%，高于 WhisperKit 的 12.8%（英文基准），中文质量需单独验证
- Foundation Models 是 3B 参数小模型，文本清洗复杂度有限，OpenAI 等更大模型在细腻 prompt following 上有优势
- 此方案完全 offline，但用户反馈安全过滤系统误伤较多

---

## 二、ASR 候选对比矩阵

| 模型 | 延迟（5s 音频） | 中文质量 | macOS 集成 | 成本 | 来源 |
|---|---|---|---|---|---|
| **Groq whisper-large-v3-turbo** | 0.15-0.32s（服务端+传输） | Whisper 系，WER ~10%（多语言基准） | REST API，低复杂度 | $0.04/h | [Groq Blog](https://groq.com/blog/whisper-large-v3-turbo-now-available-on-groq-combining-speed-quality-for-speech-recognition) |
| **Groq whisper-large-v3** | 0.2-0.4s | WER 8.4%（短音频） | REST API，低复杂度 | $0.111/h | [Groq Docs](https://console.groq.com/docs/model/whisper-large-v3) |
| **OpenAI whisper-1** | 0.8-1.6s（VPN 叠加） | 基准，中文表现稳定 | REST API | $0.006/min | 当前方案 |
| **OpenAI gpt-4o-mini-transcribe** | 实测 2.0s+（用户反馈） | 声称提升但有语言检测 bug，中英混合场景不稳定 | REST API | 略高于 whisper-1 | [OpenAI Community](https://community.openai.com/t/gpt-4o-mini-transcribe-and-gpt-4o-transcribe-not-as-good-as-whisper/1153905) |
| **OpenAI gpt-4o-transcribe** | 1.6s（实测，用户报告） | 更准确但词语丢失问题存在 | REST API | 最贵 | 同上 |
| **WhisperKit（本地 large-v3-turbo）** | 0.45s（M3，ANE） | WER 2.2%（英文），中文有轻微回归 | Swift Package，中等 | 0（本地） | [ICML 2025 论文](https://arxiv.org/abs/2507.10860) |
| **Apple SpeechAnalyzer** | ~0.07s（70x 实时） | 14% 错误率（英文），中文未知，仅 10 种语言 | 纯 Swift，最低 | 0 | [Argmax Blog](https://www.argmaxinc.com/blog/apple-and-argmax)，需 macOS 26+ |
| **Qwen3-ASR-Flash（云端 API）** | TTFT 92ms + 网络 | **中文 SOTA**：AISHELL CER 2.71%，WenetSpeech 4.97%（vs Whisper 9.86%） | REST API，中等 | $0.03/M tokens | [Qwen3-ASR 论文](https://arxiv.org/html/2601.21337v1)，[阿里云 API](https://www.alibabacloud.com/help/en/model-studio/qwen-speech-recognition) |
| **Qwen3-ASR MLX（本地）** | RTF 0.08（0.6B），约 0.4s/5s 音频 | CER 2.71%（1.7B），中文强 | Python 调用，无 Swift 原生路径 | 0（本地） | [mlx-qwen3-asr](https://github.com/moona3k/mlx-qwen3-asr) |
| **ElevenLabs Scribe v2 Realtime** | 150ms（服务端声称，不含网络） | WER 93.5% 准确率 FLEURS 30 语言 | REST API | 按分钟计费 | [ElevenLabs Blog](https://elevenlabs.io/blog/introducing-scribe-v2) |
| **Deepgram Nova-3** | <300ms | **不支持普通话（Mandarin）**，Nova-2 支持但质量一般 | REST API | $0.0043/min | [Deepgram GitHub Issue](https://github.com/orgs/deepgram/discussions/1321) |
| **Fireworks AI whisper-large-v3-turbo** | 0.45s（与 WhisperKit 相当） | 同 Whisper 基础，中文同基准 | REST API | 低 | [WhisperKit ICML 论文](https://arxiv.org/html/2507.10860v1) |
| **whisper.cpp（本地）** | M3 Pro：5s 音频约 0.3-0.5s（CoreML） | 同 Whisper 原版 | **需要 C++ 工具链**，集成复杂 | 0（本地） | [voicci.com 基准](https://www.voicci.com/blog/apple-silicon-whisper-performance.html) |

**关键结论**：
- 中文 ASR 质量排序：Qwen3-ASR > WhisperKit/Groq Whisper large-v3 > SpeechAnalyzer（英文基准，中文未知）
- Deepgram Nova-3 不支持普通话，**不可用**
- gpt-4o-mini/4o-transcribe 在 VPN 场景下延迟不降反升（实测 2s+），且有语言检测稳定性问题

---

## 三、LLM 候选对比矩阵

LLM 任务定义：输入转录文本（~30-80 中文字），去除填充词（"那个""嗯""就是说"）、修正明显口误、保留原意。输出极短。

| 模型 | TTFT | 输出速度 | 中文清洗质量 | 成本 | 来源 |
|---|---|---|---|---|---|
| **Groq llama-3.1-8b-instant** | ~80ms | 快 | 够用（8B 对简单清洗任务足够） | $0.05/M | [DEV Community 实测](https://dev.to/sundar_ramanganesh_1057a/from-7-seconds-to-500ms-the-voice-agent-optimization-secrets-4j9h) |
| **Groq llama-3.3-70b-versatile** | ~200ms | 276 tok/s | 更高，复杂清洗更准 | $0.59/M | [Artificial Analysis](https://artificialanalysis.ai/models/llama-3-3-instruct-70b/providers) |
| **OpenAI gpt-4.1-nano** | 0.70s | 138 tok/s | 高，但延迟偏高 | $0.1/M input | [Artificial Analysis](https://artificialanalysis.ai/models/gpt-4-1-nano/providers) |
| **OpenAI gpt-4o-mini** | 0.3-0.4s | 中 | 高（当前方案） | $0.15/M | 当前方案 |
| **Gemini 2.5 Flash-Lite** | 0.29-0.56s | 288-887 tok/s | 高，Google 中文支持好 | $0.0375/M | [Artificial Analysis](https://artificialanalysis.ai/models/gemini-2-5-flash-lite) |
| **Gemini 2.5 Flash** | 0.56s | 快 | 高 | $0.075/M | 同上 |
| **Apple Foundation Models** | 未知（需实测） | 3B 参数，ANE | 中文支持（简体），能力有限 | 0 | 需 macOS 26+，[Apple ML Research](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates) |
| **Claude Haiku 3.5** | 200-300ms | 快 | 高，Anthropic 中文强 | $0.8/M | 行业数据 |

**关键结论**：
- 对于"去填充词 + 修正口误"这类**结构简单的短文本清洗**，8B 模型完全够用；用 70B 是过杀
- Groq llama-3.1-8b-instant 在 TTFT 80ms 上是目前云端最快选项
- Apple Foundation Models 延迟未知，质量相对弱，但零成本且全本地，值得实测
- Gemini 2.5 Flash-Lite 是 OpenAI 之外性价比最高的备选

---

## 四、关键 Trade-off 与 Open Questions

### 已确定的事实

1. **gpt-4o-mini-transcribe / gpt-4o-transcribe 不是 VPN 场景的解法**：实测延迟比 whisper-1 更高（1.6-2.0s），且有中英混合语言检测 bug。排除。

2. **Deepgram Nova-3 不支持普通话**：用 Nova-2 会在中文质量和延迟上均劣于 Groq Whisper。排除。

3. **Groq Sydney 节点（Nov 2025 上线）是 APAC 最近节点**：中国用户 VPN 接入后若出口在亚太，RTT 改善明显。Groq 的 LPU 推理本身约 0.15-0.32s 处理 5s 音频，网络是变量。

4. **WhisperKit 是 Swift-native 最成熟的本地 ASR 方案**：Swift Package，无 C++ 依赖，macOS 14+，论文实测 0.45s 均值延迟（M3 ANE）。

5. **Qwen3-ASR 中文质量显著优于 Whisper**：AISHELL-2 CER 2.71% vs Whisper 5.06%，WenetSpeech 4.97% vs 9.86%。有云端 API（阿里云全球节点，US Virginia），也有 MLX 本地路径（纯 Python，无 Swift binding）。

### 需要实测才能决策的点

**Q1：VPN 出口对 Groq 延迟的实际影响**  
理论值 0.15-0.32s，但用户走 veee VPN 的出口位置未知。如果出口在美国西海岸，Groq 路径会绕半个地球。**建议**：用 `time curl -X POST https://api.groq.com/...` 打一次带音频的请求，实测 RTT。

**Q2：Apple Foundation Models 中文清洗质量**  
3B 模型 prompt following 有限，safety 过滤误伤。**建议**：用 10-20 条真实转录文本测试能否正确去除"那个""嗯""就是"且不破坏原意。只需 macOS 26 beta 环境。

**Q3：SpeechAnalyzer 中文 WER**  
现有 Argmax 基准用英文语料，中文质量未知。SpeechAnalyzer 仅支持 10 语言，中文简体在列但 14% 错误率（英文）提示质量中等。**建议**：录制 10 条标准普通话短句实测。

**Q4：Qwen3-ASR 云端 API 从中国 VPN 访问延迟**  
阿里云国际节点（US Virginia）vs Groq Sydney，哪个对走 veee VPN 更快，需实测。阿里云国内节点（北京）是否可直连，需核查账号权限。

**Q5：流式 ASR 是否值得**  
对 2-10s 短音频，流式（边录边发）能否减少等待？ElevenLabs Scribe v2 Realtime 声称 150ms，Fireworks 流式 0.45s。但这需要修改录音逻辑（VAD + chunked upload），工程成本 vs 延迟收益需权衡。

---

## 五、快速决策建议

**最低工程量 + 最快见效**：先把 ASR 换成 **Groq whisper-large-v3-turbo**（API 兼容 OpenAI，只改 base_url 和模型名）。预期把 ASR 侧从 ~3-4s 压到 0.3-0.5s。如果实测 Groq 网络路径比 OpenAI 快，整体端到端就能从 7-8s 降到 2-3s 量级。

**若 Groq 网络仍慢**（出口在美国）：切换 **方案 B（WhisperKit 本地）**，完全规避 VPN 影响，0.45s 本地 ASR + 0.3s Groq/Gemini LLM，端到端 <1.5s 可期。

**中文质量优先**：考虑 **Qwen3-ASR 云端 API**（阿里云 US Virginia），中文 CER 减半，但延迟需实测。

---

*调研日期：2026-04-14。Groq Sydney 节点 2025-11 上线，Qwen3-ASR 开源 2026-01，Apple SpeechAnalyzer / Foundation Models 随 macOS Tahoe 在 2025-09 正式发布。*
