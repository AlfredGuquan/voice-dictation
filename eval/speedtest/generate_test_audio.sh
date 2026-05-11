#!/bin/bash
# Regenerate the speed-test fixture audio (TTS Chinese, ~35s).
# Output: test_48k_stereo.wav (baseline native-like) + test_16k_mono.wav
# (post-#1 downsample target). bench.sh / bench_cold.sh consume these.
set -eu
cd "$(dirname "$0")"

TEXT="今天我们来讨论一下产品的迭代节奏。其实最近发现，我们每次发布之间间隔太短，导致质量保障的环节被压缩，特别是回归测试这一块。我建议下一个版本周期里，我们尝试把发布周期从一周改成两周，前后留出更多的缓冲时间。另外，关于这次新功能的设计，我觉得需要重新考虑用户的使用场景，不能只看活跃用户的反馈，要兼顾长尾的用户群体。"

say -v Tingting -o source.aiff "$TEXT"
afconvert -f WAVE -d LEF32@48000 -c 2 source.aiff test_48k_stereo.wav
afconvert -f WAVE -d LEI16@16000 -c 1 source.aiff test_16k_mono.wav
ls -la test_*.wav
