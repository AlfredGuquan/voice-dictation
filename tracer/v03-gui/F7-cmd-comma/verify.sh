#!/bin/bash
# Run demo, simulate Cmd+, via AppleScript, capture screen + probe state

set -e
cd "$(dirname "$0")/../../.."

MODE=${1:-bug}  # bug | fix

if [[ "$MODE" == "fix" ]]; then
    EXTRA="--fix"
else
    EXTRA=""
fi

# run in background
swift tracer/v03-gui/F7-cmd-comma/demo.swift $EXTRA > /tmp/f7-$MODE.log 2>&1 &
DEMO_PID=$!
sleep 2

# ensure demo window is frontmost
osascript -e 'tell application "System Events" to set frontmost of first process whose name contains "swift" to true' 2>/dev/null || true

sleep 0.5
# send Cmd+, via CGEvent (bypasses input method)
swift tracer/v03-gui/F7-cmd-comma/send-cmd-comma.swift 2>&1

sleep 0.8
screencapture -x -D 1 /tmp/f7-$MODE-after-cmdcomma.png

sleep 0.5
# kill
kill $DEMO_PID 2>/dev/null || true
wait $DEMO_PID 2>/dev/null || true

echo "--- log ---"
cat /tmp/f7-$MODE.log
echo "--- screenshot: /tmp/f7-$MODE-after-cmdcomma.png ---"
