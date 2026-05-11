#!/bin/bash
# bench_cold.sh <wav> <iterations> <label> [trigger_delay_sec]
# Like bench.sh but restarts the app before every iteration so each trigger
# measures a cold-start request (URLSession connection pool empty). Useful
# for measuring connection-prewarm savings on the first real call.

set -u

WAV="${1:?usage: bench_cold.sh <wav> [N=5] [label=test] [delay=1.0]}"
N="${2:-5}"
LABEL="${3:-test}"
DELAY="${4:-1.0}"
ROOT=/Users/alfred.gu/Desktop/2-projects/voice-dictation
APP=$ROOT/.build/debug/VoiceDictation
LOG=/tmp/vd_bench_${LABEL}.log
TRIGGER=/tmp/voice-dictation-trigger.json

[ -f "$WAV" ] || { echo "wav not found: $WAV" >&2; exit 1; }
[ -x "$APP" ] || { echo "app not built: $APP — run swift build" >&2; exit 1; }

DUR=$(afinfo "$WAV" 2>/dev/null | awk '/estimated duration/ {print $3}')
DUR=${DUR:-1.0}

: > "$LOG"
echo "[bench_cold] label=$LABEL wav=$(basename "$WAV") duration=${DUR}s N=$N trigger_delay=${DELAY}s"

for i in $(seq 1 $N); do
    pkill -f VoiceDictation 2>/dev/null
    sleep 1
    rm -f "$TRIGGER"

    ITER_LOG=/tmp/vd_bench_${LABEL}_iter${i}.log
    : > "$ITER_LOG"
    "$APP" > "$ITER_LOG" 2>&1 &
    APP_PID=$!

    for _ in $(seq 1 60); do
        grep -q "\[Pipeline\] Ready" "$ITER_LOG" && break
        sleep 0.25
    done
    if ! grep -q "\[Pipeline\] Ready" "$ITER_LOG"; then
        echo "  run $i: app did not start"
        kill $APP_PID 2>/dev/null
        continue
    fi

    # Wait `trigger_delay` after ready to give prewarm a chance to complete
    # (or to keep the gap consistent when prewarm is disabled).
    sleep "$DELAY"

    echo "{\"wavPath\":\"$WAV\",\"recordDuration\":$DUR}" > "$TRIGGER"
    for _ in $(seq 1 120); do
        sleep 0.5
        if grep -q "\[Pipeline\] timing:" "$ITER_LOG"; then break; fi
    done

    LAST=$(grep "\[Pipeline\] timing:" "$ITER_LOG" | tail -1)
    echo "  run $i: $LAST"
    cat "$ITER_LOG" >> "$LOG"
    echo "--- run $i end ---" >> "$LOG"
    kill $APP_PID 2>/dev/null
    wait 2>/dev/null || true
done

echo ""
echo "=== stats (label=$LABEL, cold-start every run) ==="
python3 - "$LOG" <<'PY'
import re, sys, statistics
lines = open(sys.argv[1]).read().splitlines()
rx = re.compile(r"\[Pipeline\] timing: rec=([\d.]+)s asr=([\d.]+)s llm=([\d.]+)s inject=([\d.]+)s")
asr, llm, inj = [], [], []
for ln in lines:
    m = rx.search(ln)
    if m:
        asr.append(float(m.group(2)))
        llm.append(float(m.group(3)))
        inj.append(float(m.group(4)))
def fmt(arr):
    if not arr: return "n=0"
    if len(arr) == 1: return f"n=1 val={arr[0]:.3f}s"
    return f"n={len(arr)} median={statistics.median(arr):.3f}s mean={statistics.mean(arr):.3f}s min={min(arr):.3f}s max={max(arr):.3f}s"
print(f"  asr    {fmt(asr)}")
print(f"  llm    {fmt(llm)}")
print(f"  inject {fmt(inj)}")
total = [a+l+i for a,l,i in zip(asr, llm, inj)]
print(f"  total  {fmt(total)}")
PY
