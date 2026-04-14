#!/bin/bash
# Capture F5 toast demo while switching frontmost app to Finder
# Run from repo root

set -e

cd "$(dirname "$0")/../../.."

# start demo in background
swift tracer/v03-gui/F5-toast/demo.swift > /tmp/f5-demo.log 2>&1 &
DEMO_PID=$!

sleep 0.8
# switch foreground to TextEdit (make new doc and bring it front)
osascript -e 'tell application "TextEdit" to activate' \
          -e 'tell application "TextEdit" to make new document' \
          -e 'tell application "TextEdit" to set bounds of window 1 to {100, 100, 900, 700}' || true

sleep 1.2
screencapture -x /tmp/f5-toast-with-textedit.png

sleep 2.5
screencapture -x /tmp/f5-toast-final.png

# close TextEdit doc
osascript -e 'tell application "TextEdit" to close every document without saving' || true
osascript -e 'tell application "TextEdit" to quit' || true

wait $DEMO_PID 2>/dev/null || true
echo "screenshots: /tmp/f5-toast-with-finder.png, /tmp/f5-toast-final.png"
ls -la /tmp/f5-toast-*.png
