## Per-row

| ID | Winner | 关键证据 |
|---|---|---|
| 001 | sensevoice | Whisper 丢全部标点；Qwen3 把逗号换问号改变语气；SenseVoice 完美 |
| 002 | qwen3 | Whisper 繁体化+BUG 大写+丢句号；SenseVoice 少英文前后空格；Qwen3 完美 |
| 003 | qwen3 | Whisper 丢全部语气停顿；SenseVoice 少一个逗号；Qwen3 两个停顿都保留 |
| 004 | sensevoice | Whisper 繁体+"纪要"→"机要"硬伤；SenseVoice/Qwen3 均完美（tie，但 SV 更典型） |
| 005 | qwen3 | Whisper 分支→分区；SenseVoice 空格不一致；Qwen3 空格+术语完美 |
| 006 | whisper | Whisper 正确保留"Cursor"；SV "科s"、Qwen3 "科色" 都把英文名音译成乱码 |
| 007 | qwen3 | Whisper pnpm→pmpm + "装依赖"→"装一来"；SV install→instore 双错；Qwen3 拼读但语义全对 |
| 008 | sensevoice | 三家都正确，SV 语义+标点最完整（Qwen3 404→四零四不利于机器指令场景） |
| 009 | sensevoice | 三家都把 Run→Return；但 SV 唯一保留 "tests" 复数 |
| 010 | tie whisper/qwen3 | 三家都错了 diff；但 differ 比 different 更接近原词 |
| 011 | sensevoice | Whisper 繁体+Q2→QR 硬伤；Qwen3 Q2→Q二不利；SV 少一个逗号但 Q2 正确 |
| 012 | sensevoice | Whisper 繁体+空格代标点；SV 完美；Qwen3 缺席 |
| 013 | whisper | Whisper 内容完整标点齐；SV 丢"的"；Qwen3 缺席 |
| 014 | whisper | Whisper 内容完整；SV 丢"的"；Qwen3 缺席 |
| 015 | sensevoice | Whisper "待办"→"大半"+"紧急的"→"请记得"双硬伤；SV 仅"待办/代办"同音小错 |
| 016 | sensevoice | 两家都丢"能"；SV 多标点；Qwen3 缺席 |
| 017 | whisper | Whisper 保留 CamelCase WhisperService/SenseVoice；SV 拆成小写丢术语 |
| 018 | sensevoice | Whisper race→raise 硬伤（含义改变）；SV 术语全对 |
| 019 | whisper | Whisper 仅错 Claude→Cloud；SV 把 "prompt caching" 直接丢成 "pro" 是严重丢段 |
| 020 | whisper | Whisper typo→tipo 小错；SV commit→commitit + typo→tple 双错 |
| 021 | whisper | Whisper state 正确；SV state→states 复数错 |
| 022 | whisper | Whisper 丢冒号/斜杠但整体框架对；SV package.json→"package dot Jasonson" 近乎不可读 |
| 023 | whisper | Whisper downsample→"当sample"+喂→"位"小错；SV "当simle" 更糟 |
| 024 | whisper | 都错了 Sonnet/Opus；但 Whisper 保留 Anthropic，SV "andropsonny" 一片糊 |
| 025 | whisper | Whisper 术语全对只错 mono→monotone；SV ffmpeg→FFP + webm→wem 连续硬伤 |
| 026 | whisper | Whisper 完美；SV async→Aing + 丢 promise 严重丢段 |
| 027 | sensevoice | Whisper ANE→AME + 繁体；SV 大小写差但术语形状接近 |
| 028 | sensevoice | Whisper 丢中间逗号；SV 句子完整标点齐 |
| 029 | sensevoice | Whisper 把英文整句"翻译+幻觉"为中文乱码；SV 仅 curl→core 小错 |
| 030 | sensevoice | Whisper 把英文翻成中文（严重事故）；SV async→Ithink 小错但英文结构保留 |
| 031 | sensevoice | Whisper 幻觉"Kubernetes 3SR"（无中生有）；SV 术语模糊但无幻觉 |
| 032 | whisper | Whisper cache 正确；SV cache→cachet 小错 |
| 033 | whisper | Whisper SwiftUI/pipeline/ASR/LLM/HTTP 全保留；SV pipeline→paline |
| 034 | sensevoice | Whisper "逐字符"→"竹字符" 硬伤；SV "逐字符"正确 |
| 035 | sensevoice | Whisper "边际"→"编辑"硬伤（语义完全变）；SV "边际"正确 |
| 036 | whisper | Whisper Groq/Whisper/VPN/Sydney 全对；SV whisper→"ws" + VPN→"V片" |
| 037 | whisper | Whisper 整体框架接近；SV Typeless 直接丢 + stateatus 乱拼 |
| 038 | sensevoice | Whisper "出结果"→"出结构"+"流式"→"流逝"双字形错；SV 两词都正确 |
| 039 | sensevoice | Whisper "验收"→"应用"改变语义（这是核心动作词）；SV 保留"验收" |
| 040 | whisper | Whisper 保留 Voice Dictation 正确拼写；SV voice→"voice dation" + 断句错 |

## 按场景聚合

**短中文日常（001-004, 011-016）**：SenseVoice 最稳，标点语义双全。Qwen3 在有数据的条目里几乎满分，但会把数字读成汉字（Q2→Q二、404→四零四）对 coding agent 是硬伤。Whisper 统一繁体化+丢标点，不适合直接注入。

**中英混合代码术语（005, 017-028, 031-040）**：Whisper 明显领先，CamelCase/pnpm/ffmpeg/Groq/SwiftUI/Voice Dictation 等专业术语几乎全对；SenseVoice 经常把英文拆成小写碎片或音译成中文乱码（package.json→"package dot Jasonson"、webm→"wem"）。但 Whisper 在常见字形混淆上会出硬伤（race→raise、出结果→出结构、边际→编辑、验收→应用、逐→竹、紧急的→请记得），且会**幻觉**"Kubernetes 3SR"这种凭空造词。

**纯英文（009, 010, 029, 030）**：SenseVoice 最稳。Whisper 在 029/030 把英文整句"翻译"成中文，属于灾难性失控——这对英文 prompt 场景是 dealbreaker。

**犹豫/语气词（003, 014, 026）**：Qwen3 对"嗯、那个"的停顿最贴原文，SenseVoice 次之，Whisper 倾向丢掉标点。

## 总体排名

1. **SenseVoice** — 40/40 全量覆盖；中文标点/语义/语气最稳；英文 preserved 不会被翻译；唯一会幻觉的场景是英文术语音译成碎片，但不会"无中生有"。硬伤率最低。
2. **Whisper API** — 中英混合术语保真最强，但有三类"致命事故"：整句英文被翻译成中文（029/030）、凭空幻觉词（031 Kubernetes）、字形混淆把关键动词替换（验收→应用、边际→编辑）。而且默认繁体化+丢中文标点，写回光标需要二次清洗。
3. **Qwen3-ASR (仅 11 条)** — 在这 11 条里短中文+混合的质量最高（标点、语气、空格都对），但延迟不可用+覆盖不足无法做整体推荐，且数字→汉字（Q2→Q二、404→四零四）在 coding 场景是硬伤。

## 推荐

**voice-dictation 给 coding agent 当输入 → 推荐 SenseVoice，Whisper 做 LLM 清洗前的 fallback/参考**。

理由：
- coding agent 场景里 **"英文整句被翻成中文"和"凭空幻觉术语"是不可接受的**（Whisper 029/030/031 暴露了这两个事故模式）。SenseVoice 错了会碎但不会离题，后接 LLM 清洗能救回来；Whisper 的事故是语义级的，LLM 救不回。
- 中文标点/语义 SenseVoice 直接可用，Whisper 需要全局简繁转换+补标点。
- Qwen3 现阶段 RTF 20-100 无法上线；但如果未来 MLX 侧延迟下来，在短中文/含语气词的 dictation 场景它的文本质量最接近手打。

Trade-off：
- SenseVoice 在 19、22、36 这类**"术语密集 + 长英文短语"**上会丢段（prompt caching→pro、package.json→Jasonson），需要依赖后置 LLM 清洗 + 项目专有名词词表补救。
- 如果主场景是**纯英文 prompt 且包含项目专名**，Whisper 单模型略占优，但要接受 029/030 那种整句乱翻的偶发事故——建议做"英文占比>80% 时 fallback 到 Whisper"的双引擎路由。
