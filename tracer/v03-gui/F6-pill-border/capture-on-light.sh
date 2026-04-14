#!/bin/bash
# Capture pill against a white TextEdit window to reveal shadow-rect artifact

set -e
cd "$(dirname "$0")/../../.."

# Launch TextEdit with a maximized white doc on built-in display
osascript <<'OSA'
tell application "TextEdit"
    activate
    make new document
    set bounds of front window to {0, 40, 1470, 956}
end tell
OSA

sleep 1.2

for v in prod fixed shadow-on-container no-nsshadow; do
    ./tracer/v03-gui/F6-pill-border/.build/debug/F6PillDemo $v > /dev/null 2>&1
    mv /tmp/f6-$v.png /tmp/f6-$v-light.png
    echo "captured /tmp/f6-$v-light.png"
done

osascript -e 'tell application "TextEdit" to close every document without saving'
osascript -e 'tell application "TextEdit" to quit'
