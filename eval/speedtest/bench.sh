#!/bin/bash
# bench.sh <wav> <iterations> <label>
# Boots the VoiceDictation app, triggers the dictation pipeline N times against
# the given WAV file, and prints per-stage timing (asr / llm / inject).

set -u

WAV="${1:?usage: bench.sh <wav> [N=5] [label=test]}"
N="${2:-5}"
LABEL="${3:-test}"
ROOT=/Users/alfred.gu/Desktop/2-projects/voice-dictation
APP=$ROOT/.build/debug/VoiceDictation
LOG=/tmp/vd_bench_${LABEL}.log
TRIGGER=/tmp/voice-dictation-trigger.json

[ -f "$WAV" ] || { echo "wav not found: $WAV" >&2; exit 1; }
[ -x "$APP" ] || { echo "app not built: $APP — run swift build" >&2; exit 1; }

DUR=$(afinfo "$WAV" 2>/dev/null | awk '/estimated duration/ {print $3}')
DUR=${DUR:-1.0}

pkill -f VoiceDictation 2>/dev/null
sleep 1
rm -f "$TRIGGER"
: > "$LOG"

"$APP" > "$LOG" 2>&1 &
APP_PID=$!

# wait for "[Pipeline] Ready"
for _ in $(seq 1 60); do
    grep -q "\[Pipeline\] Ready" "$LOG" && break
    sleep 0.25
done
grep -q "\[Pipeline\] Ready" "$LOG" || { echo "app did not become ready"; kill $APP_PID 2>/dev/null; exit 1; }

echo "[bench] label=$LABEL wav=$(basename "$WAV") duration=${DUR}s N=$N pid=$APP_PID"

for i in $(seq 1 $N); do
    BEFORE=$(grep -c "\[Pipeline\] timing:" "$LOG" || true)
    BEFORE=${BEFORE:-0}
    echo "{\"wavPath\":\"$WAV\",\"recordDuration\":$DUR}" > "$TRIGGER"

    # wait up to 60s for a new timing line
    for _ in $(seq 1 120); do
        sleep 0.5
        AFTER=$(grep -c "\[Pipeline\] timing:" "$LOG" || true)
        AFTER=${AFTER:-0}
        [ "$AFTER" -gt "$BEFORE" ] && break
    done
    LAST=$(grep "\[Pipeline\] timing:" "$LOG" | tail -1)
    echo "  run $i: $LAST"
    sleep 1
done

kill $APP_PID 2>/dev/null
wait 2>/dev/null || true

echo ""
echo "=== stats (label=$LABEL) ==="
python3 - "$LOG" <<'PY'
import re, sys, statistics
lines = open(sys.argv[1]).read().splitlines()
rx = re.compile(r"\[Pipeline\] timing: rec=([\d.]+)s asr=([\d.]+)s llm=([\d.]+)s inject=([\d.]+)s")
rec, asr, llm, inj = [], [], [], []
for ln in lines:
    m = rx.search(ln)
    if m:
        rec.append(float(m.group(1)))
        asr.append(float(m.group(2)))
        llm.append(float(m.group(3)))
        inj.append(float(m.group(4)))
def fmt(arr):
    if not arr:
        return "n=0"
    if len(arr) == 1:
        return f"n=1 val={arr[0]:.3f}s"
    return f"n={len(arr)} median={statistics.median(arr):.3f}s mean={statistics.mean(arr):.3f}s min={min(arr):.3f}s max={max(arr):.3f}s"
print(f"  asr    {fmt(asr)}")
print(f"  llm    {fmt(llm)}")
print(f"  inject {fmt(inj)}")
total = [a+l+i for a,l,i in zip(asr, llm, inj)]
print(f"  total  {fmt(total)}    (asr+llm+inject; rec is the wav duration not pipeline time)")
PY
