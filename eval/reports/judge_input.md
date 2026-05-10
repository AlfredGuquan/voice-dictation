# ASR 引擎对比评判任务
你是一位严谨的 ASR（语音识别）评估员。以下 40 条对照数据中，每条包含：
- **Ground Truth**：用户照稿念读的原文
- 三个模型的转写结果：openai_whisper_api, sensevoice, qwen3_asr_mlx

> 注意：`qwen3_asr_mlx` 因推理延迟过高（单条 RTF 20-100，每条 60-230 秒）只跑了 11/40 就被终止；标记 `(MISSING)` 的行表示该 engine 未产出结果。请基于现有数据做判断，对 Qwen3 的结论请说明是"基于 11 条样本"。

## 评判规则
1. **只看文本内容**，不考虑延迟或 CER/WER 等机器指标——那些由别的通道处理
2. 对每一条，指出 **哪个模型转写得最好**，并给出**具体证据**（哪里错了、漏了、幻觉了、标点处理如何）
3. 关注维度：语义保真、专有名词/英文术语准确性、中英混合处理、数字/版本号、标点、幻觉（虚构内容）
4. 区分"小瑕疵"（标点、语气词）和"硬伤"（关键术语错、语义变了、丢字漏段）
5. 最后给出**总体排名**和**推荐**，必须附证据——哪些条/哪类场景决定了你的判断

## 输出格式（严格遵守）
```markdown
## Per-row
| ID | Winner | 关键证据（一句话） |
| 001 | sensevoice | Whisper 丢了全部标点；Qwen3 把"，"换成"？" |
... (40 行)

## 按场景聚合
（比如：中英混合类、长句类、含犹豫词类哪个赢）

## 总体排名
1. [engine] — 理由
2. ...
3. ...

## 推荐
根据用户的使用场景（voice-dictation 给 coding agent 当输入），推荐哪个、为什么、有什么 trade-off
```

## 数据

### 001  `[short / zh / daily]`
**Ground Truth**: 今晚吃什么，你决定吧。
- `openai_whisper_api`: 今晚吃什么你决定吧
- `sensevoice`: 今晚吃什么，你决定吧。
- `qwen3_asr_mlx`: 今晚吃什么？你决定吧。

### 002  `[short / zh / daily]`
**Ground Truth**: 这个 bug 我晚点修。
- `openai_whisper_api`: 這個BUG我晚點修
- `sensevoice`: 这个bug我晚点修。
- `qwen3_asr_mlx`: 这个 bug 我晚点修。

### 003  `[short / zh / hesitation]`
**Ground Truth**: 嗯……那个……我想想再说。
- `openai_whisper_api`: 嗯那个我想想再说
- `sensevoice`: 嗯，那个我想想再说。
- `qwen3_asr_mlx`: 嗯，那个，我想想再说。

### 004  `[short / zh / daily]`
**Ground Truth**: 麻烦你把会议纪要发我一份。
- `openai_whisper_api`: 麻煩你把會議機要發我一份
- `sensevoice`: 麻烦你把会议纪要发我一份。
- `qwen3_asr_mlx`: 麻烦你把会议纪要发我一份。

### 005  `[short / mixed / coding]`
**Ground Truth**: 把这个 commit 推到 main 分支。
- `openai_whisper_api`: 把这个commit推到main分区
- `sensevoice`: 把这个commit推到 main分支。
- `qwen3_asr_mlx`: 把这个 commit 推到 main 分支。

### 006  `[short / mixed / coding]`
**Ground Truth**: 打开 Cursor 重启一下。
- `openai_whisper_api`: 打開Cursor重啟一下
- `sensevoice`: 打开科s重启一下。
- `qwen3_asr_mlx`: 打开科色，重启一下。

### 007  `[short / mixed / coding]`
**Ground Truth**: 用 pnpm install 装依赖。
- `openai_whisper_api`: 用pmpm install 装一来
- `sensevoice`: 用PMPMinsstore装依赖。
- `qwen3_asr_mlx`: 用 P N P M install 安装依赖。

### 008  `[short / mixed / terms]`
**Ground Truth**: 这个 endpoint 返回 404。
- `openai_whisper_api`: 這個endpoint返回404
- `sensevoice`: 这个endpoint返回404。
- `qwen3_asr_mlx`: 这个 endpoint 返回四零四。

### 009  `[short / en / coding]`
**Ground Truth**: Run the tests and push it.
- `openai_whisper_api`: Return the test and push it.
- `sensevoice`: Return the tests, and push it.
- `qwen3_asr_mlx`: Return the test and push it.

### 010  `[short / en / coding]`
**Ground Truth**: Show me the diff for this file.
- `openai_whisper_api`: Show me the differ for this file
- `sensevoice`: Show me the different for this file.
- `qwen3_asr_mlx`: Show me the differ for this file.

### 011  `[medium / zh / daily]`
**Ground Truth**: 明天上午十点有一个会，麻烦帮我提醒一下，内容大概是讨论 Q2 的规划。
- `openai_whisper_api`: 明天上午10點有一個會,麻煩幫我提醒一下,內容大概是討論QR的規劃。
- `sensevoice`: 明天上午10点有一个会，麻烦帮我提醒一下内容大概是讨论Q2的规划。
- `qwen3_asr_mlx`: 明天上午十点有一个会，麻烦帮我提醒一下。内容大概是讨论Q二的规划。

### 012  `[medium / zh / daily]`
**Ground Truth**: 我觉得这个方案不太行，因为延迟还是太高，用户体验不好。
- `openai_whisper_api`: 我覺得這個方案不太行 因為延遲還是太高 用戶體驗不好
- `sensevoice`: 我觉得这个方案不太行，因为延迟还是太高，用户体验不好。
- `qwen3_asr_mlx`: (MISSING)

### 013  `[medium / zh / hesitation]`
**Ground Truth**: 等一下，我先把刚才的思路整理一下，然后再告诉你接下来该怎么做。
- `openai_whisper_api`: 等一下,我先把刚才的思路整理一下,然后再告诉你接下来该怎么做。
- `sensevoice`: 等一下，我先把刚才思路整理一下，然后再告诉你接下来该怎么做。
- `qwen3_asr_mlx`: (MISSING)

### 014  `[medium / zh / hesitation]`
**Ground Truth**: 刚刚那个，就是说，你之前提到的那个问题，我想再确认一下。
- `openai_whisper_api`: 刚刚那个就是说你之前提到的那个问题我想再确认一下
- `sensevoice`: 刚刚那个就是说你之前提到那个问题，我想再确认一下。
- `qwen3_asr_mlx`: (MISSING)

### 015  `[medium / zh / daily]`
**Ground Truth**: 请把今天的待办事项按优先级排序，紧急的放最上面。
- `openai_whisper_api`: 请把今天的大半事项按优先级排序,请记得放上面。
- `sensevoice`: 请把今天的代办事项按优先级排序，紧急的放上面。
- `qwen3_asr_mlx`: (MISSING)

### 016  `[medium / zh / fast]`
**Ground Truth**: 声音快起来的时候要能识别得准，这对模型来说是个挑战。
- `openai_whisper_api`: 声音快起来的时候要识别的准 这对模型来说是个挑战
- `sensevoice`: 声音快起来的时候要识别的准，这对模型来说是个挑战。
- `qwen3_asr_mlx`: (MISSING)

### 017  `[medium / mixed / coding]`
**Ground Truth**: 把 WhisperService 换成 SenseVoice 的调用，接口保持兼容。
- `openai_whisper_api`: 把WhisperService换成SenseVoice的调用接口保持兼容
- `sensevoice`: 把whisper service换成sense voice的调用接口保持兼容。
- `qwen3_asr_mlx`: (MISSING)

### 018  `[medium / mixed / coding]`
**Ground Truth**: 这个 function 里面有个 race condition，你 review 一下。
- `openai_whisper_api`: 这个function里面有个raise condition,你review一下
- `sensevoice`: 这个 function里面有个race condition，你review一下。
- `qwen3_asr_mlx`: (MISSING)

### 019  `[medium / mixed / terms]`
**Ground Truth**: 帮我查一下 Claude API 的 rate limit 是多少，顺便看下 prompt caching 的文档。
- `openai_whisper_api`: 帮我查一下Cloud API的Rate Limit是多少 顺便看一下Prompt Caching的文档
- `sensevoice`: 帮我查一下cloud API的rate limit是多少，顺便看一下pro的文档。
- `qwen3_asr_mlx`: (MISSING)

### 020  `[medium / mixed / coding]`
**Ground Truth**: 我刚才 push 的 commit 里有个 typo，麻烦 revert 一下，或者直接 amend。
- `openai_whisper_api`: 我刚才push commit里有个tipo 麻烦revert一下或者直接amend
- `sensevoice`: 我刚才push commitit里有个tple，麻烦revert一下，或者直接amend。
- `qwen3_asr_mlx`: (MISSING)

### 021  `[medium / mixed / coding]`
**Ground Truth**: 把 React component 的 state 拆成两个 useState，一个管 loading 一个管 error。
- `openai_whisper_api`: 把 React Component 的 state 拆成兩個 use state 一個管 loading 一個管 error
- `sensevoice`: 把 react component的 states拆成两个 use state，一个管 loading一个管 error.
- `qwen3_asr_mlx`: (MISSING)

### 022  `[medium / mixed / coding]`
**Ground Truth**: 在 package.json 里加一个 script 叫 dev:local，指向 tsx watch src/main.ts。
- `openai_whisper_api`: 在 package.json 里加一个 script 叫 devlocal 指向 tsx watch src main.ts
- `sensevoice`: 在 package dot Jasonson里加一个 script叫de Bo指向 T S X watch S RRC main dot T S.
- `qwen3_asr_mlx`: (MISSING)

### 023  `[medium / mixed / numbers]`
**Ground Truth**: 把音频从 48 kHz downsample 到 16 kHz 再喂给模型。
- `openai_whisper_api`: 把音频从48k赫兹当sample到16k赫兹再喂给模型
- `sensevoice`: 把音频从48K赫兹当simle到16K赫兹再位给模型。
- `qwen3_asr_mlx`: (MISSING)

### 024  `[medium / mixed / terms]`
**Ground Truth**: Anthropic 的 Sonnet 4.6 和 Opus 4.7 哪个更适合做 tool use？
- `openai_whisper_api`: Anthropic的Sony 4.6和OPPO 4.7哪個更適合做Tour Use
- `sensevoice`: andropsonny4.6和ops4.7，哪个更适合做tous？
- `qwen3_asr_mlx`: (MISSING)

### 025  `[medium / mixed / coding]`
**Ground Truth**: 用 ffmpeg 把 webm 转成 wav，采样率指定 16000，mono 通道。
- `openai_whisper_api`: 用 ffmpeg 把 webm 转成 wav 采样率指定 16000 monotone 的
- `sensevoice`: 用FFP把wem转成WAB采样率指定16000mon通道。
- `qwen3_asr_mlx`: (MISSING)

### 026  `[medium / mixed / hesitation]`
**Ground Truth**: 那个 async function 没有 await，导致 promise 被 swallow 了。
- `openai_whisper_api`: 那个async function没有await,导致promise被swallow了
- `sensevoice`: 那个Aing function没有 await导致被 swallow。
- `qwen3_asr_mlx`: (MISSING)

### 027  `[medium / mixed / terms]`
**Ground Truth**: Apple Silicon 的 ANE 跑 CoreML 模型会比 GPU 快吗？
- `openai_whisper_api`: Apple Silicon的AME跑Core ML模型會比GPU快嗎?
- `sensevoice`: apple silicon anE跑 coreml模型会比Gpu快吗？
- `qwen3_asr_mlx`: (MISSING)

### 028  `[medium / mixed / terms]`
**Ground Truth**: 这个 bug 我觉得跟 React 18 的 StrictMode 有关，双重调用导致的。
- `openai_whisper_api`: 这个bug我觉得跟react18的scriptmode有关 双重调用导致的
- `sensevoice`: 这个bug我觉得跟react18的script mode有关，双重调用导致的。
- `qwen3_asr_mlx`: (MISSING)

### 029  `[medium / en / coding]`
**Ground Truth**: Spin up a test server on port 3000 and curl the health endpoint.
- `openai_whisper_api`: 3200 ignorance abort 测试服务后,确定疾病的头发
- `sensevoice`: Spin up a testover on port 3000 and core the health endpoint.
- `qwen3_asr_mlx`: (MISSING)

### 030  `[medium / en / coding]`
**Ground Truth**: Refactor this component so the async logic lives in a custom hook.
- `openai_whisper_api`: 我們將這些元件重新設計,使ASync的邏輯生存在客戶的Hook上。
- `sensevoice`: Refactor this component so that Ithink logic lives in a customer hook.
- `qwen3_asr_mlx`: (MISSING)

### 031  `[long / mixed / coding]`
**Ground Truth**: 我想做一个语音输入法的 eval 框架，先用 OpenAI Whisper 作为 baseline，然后对比 SenseVoice 和 Qwen3-ASR 这两个本地模型，主要看 CER 和端到端 latency。
- `openai_whisper_api`: 我想做一个语音输入法的EVA框架 先用OpenAI Whisper作为baseline 然后对比Sense, Waze和Kubernetes 3SR这两个本地模型 主要看CER和端到端Latency
- `sensevoice`: 我想作为一个语音输入法的一va框架，先用open airI whispers作为baseline，然后对比sanense voice和Qban3SR这两个本地模型主要看CER和端到端latency。
- `qwen3_asr_mlx`: (MISSING)

### 032  `[long / mixed / coding]`
**Ground Truth**: 刚才那个 pull request 里，ReviewService 这个类的职责太多了，又做 fetch 又做 cache 又做 diff 计算，我觉得应该拆成三个独立的 service，每个只负责一件事。
- `openai_whisper_api`: 刚才那个pool request里review service这个类的职责太多了 又做fetch又做cache又做diff计算 我觉得应该拆成三个独立的service 每个只负责一件事
- `sensevoice`: 刚才那个p request里review service这个类的职责太多了，又做fetch，又做cachet，又做diff计算。我觉得应该拆成三个独立的service，每个只负责一件事。
- `qwen3_asr_mlx`: (MISSING)

### 033  `[long / mixed / coding]`
**Ground Truth**: 这个项目的架构是这样的：前端用 SwiftUI，中间有一个 pipeline 负责协调录音、ASR、LLM 清洗和文本注入，后端的 ASR 和 LLM 都是通过 HTTP 调用云端服务的。
- `openai_whisper_api`: 这个项目的架构是这样的 前端用Swift UI 中间有个Pipeline负责协调录音 ASR LLM清洗和文本注入 后端的ASR和LLM都是通过HTTP调用云端服务的
- `sensevoice`: 这个项目的架构是这样的，前端用swift uI中间有一个paline负责协调录音ASRLLM清洗和文本注入后端的ASR和LLM都是通过HTTP调用云端服务的。
- `qwen3_asr_mlx`: (MISSING)

### 034  `[long / mixed / coding]`
**Ground Truth**: 我现在遇到一个问题，就是在 macOS 上用 CGEvent 注入文字的时候，中文和英文的处理方式不一样，CJK 字符如果用逐字符 keyDown 会有编码问题，所以我改成了剪贴板粘贴法。
- `openai_whisper_api`: 我现在遇到一个问题,就是在macOS上用cgevent注入文字的时候,中文和英文的处理方式不一样,cjk字符如果用竹字符keydown会有编码问题,所以我改成了剪贴版粘贴法。
- `sensevoice`: 我现在遇到一个问题，就是在mac OS上用cgeven注入文字的时候，中文和英文的处理方式不一样。CJK字符如果用逐字符key down会有编码问题，所以我改成了剪切板粘贴法。
- `qwen3_asr_mlx`: (MISSING)

### 035  `[long / mixed / coding]`
**Ground Truth**: 如果 SenseVoice 的 CER 比 Whisper 低 50%，但延迟高了两倍，那我们还是不要换，因为 voice-dictation 的核心指标是端到端延迟，accuracy 的边际收益比延迟的边际损失要小。
- `openai_whisper_api`: 如果SenseVoice的CER比Whisper低50%,但延遲高了兩倍,那我們還是不要換,因為VoiceDictation的核心指標是端到端延遲,Accuracy的編輯收益比延遲的編輯損失要小。
- `sensevoice`: 如果sans voiceice的ceR比whiser低50%，但延迟高了两倍，那我们还是不要换。因为voice dictation的核心指标是端到端延迟 accuracy的边际收益比延迟的边际损失要小。
- `qwen3_asr_mlx`: (MISSING)

### 036  `[long / mixed / coding]`
**Ground Truth**: 下一步我想先实测一下 Groq 的 whisper-large-v3-turbo 从上海走 VPN 到 Sydney 节点的真实 RTT，然后对比 OpenAI Whisper-1 走同一个出口的延迟，看看 Groq 是不是真的能快到 500 毫秒以内。
- `openai_whisper_api`: 下一步我想先实测一下Grok的WhisperLarge V3 Turbo 从上海出VPN到Sydney节点的真实RTT 然后对比OpenAI WhisperOne走同一个出口的延迟 看看Grok是不是真的快到500毫秒以内
- `sensevoice`: 下一步我想先实测一下glock的ws largege v从上海出V片到sydney节点的真实tt，然后对比openaiiws one走同一个出口的延迟，看看glock是不是真的快到500毫秒以内。
- `qwen3_asr_mlx`: (MISSING)

### 037  `[long / mixed / coding]`
**Ground Truth**: 我刚才在 Typeless 的 SQLite 里看到 history 表有一个 edited_text 字段，按理说应该是用户编辑后的文本，但在我本地全部都是空的，status 都是 NOT_EXTRACTED，估计是服务端回填的逻辑没触发。
- `openai_whisper_api`: 我刚才在Tabless的CircleLight里看到History表有一个edited text字段 按理说应该是用过编辑后的文本,但我在本地全部都是空的 Status都是not extracted,估计是服务端回填的逻辑没触发
- `sensevoice`: 我刚才在tusciite里看到history表有一个edited text字段。按理说应该是用户编辑后的文本，但我在本地全部都是空的stateatus都是not extracted，估计是服务端回填的逻辑没触发。
- `qwen3_asr_mlx`: (MISSING)

### 038  `[long / mixed / coding]`
**Ground Truth**: 目前 pipeline 是串行的，先 ASR 再 LLM，总延迟是两个加起来。其实如果 ASR 出结果的时候就启动 LLM 的流式调用，理论上可以把 LLM 的 TTFT 叠在 ASR 后半段里，端到端能省几百毫秒。
- `openai_whisper_api`: 目前Pipeline是串行的,先ASR再LLM,总延迟是两个加起来 其实如果ASR出结构的时候,就启用LLM的流逝调用 理论上可以把LLM的TTFT叠在ASR后半段里,端到端能省几百毫秒
- `sensevoice`: 目前，paline是串行的，先asR在LM总延迟是两个加起来。其实如果asR出结果的时候，就启用LM的流式调用。理论上可以把LM的ttft叠在asR后半段里，端到端能省几百毫秒。
- `qwen3_asr_mlx`: (MISSING)

### 039  `[long / mixed / coding]`
**Ground Truth**: 这个功能的验收标准是：按热键说话，松开之后两秒内文字出现在光标位置，而且清洗之后不能丢原意，口语填充词像嗯、那个、就是说要被去掉，但是专业术语和数字不能被改动。
- `openai_whisper_api`: 这个功能的应用标准是按热键说话,松开之后两秒内文字出现在光标位置,而且清洗之后不能丢原意,口语填充词像嗯那个就是说要被去掉,但是专业术语和数字不能被改动。
- `sensevoice`: 这个功能的验收标准是按热键说话，松开之后，2秒内文字出现在光标位置，而且清洗之后不能丢原意。口语填充词像那个就是说要被去掉，但是专业术语和数字不能被改动。
- `qwen3_asr_mlx`: (MISSING)

### 040  `[long / mixed / daily]`
**Ground Truth**: 我觉得 voice-dictation 下一步要解决的最大问题不是准确率，而是用户在什么场景下会想到用它。目前我自己都只在 coding agent 场景下用，IM 聊天的时候还是习惯打字，说明这个工具的 discoverability 和触发成本还有问题。
- `openai_whisper_api`: 我觉得Voice Dictation下一步要解决的最大问题不是准确率,而是用户在什么场景下会想到用它 目前我自己都只在Coding Agent的场景下用,IAM聊天的时候还是习惯打字 说明这个工具的Discoverability和触发成本还是有问题
- `sensevoice`: 我觉得voice dation下一步要解决的最大问题不是准确率，而是用户在什么场景下会想到用它。目前我自己都只在coding agent的场景下，用I am聊天的时候，还是习惯打字，说明这个工具的discoverability和触发成本还是有问题。
- `qwen3_asr_mlx`: (MISSING)

