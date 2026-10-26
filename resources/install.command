#!/bin/bash
# Installs Headset Lock from the disk image, with no trip to Privacy and Security.
# In Terminal type "bash ", drag this file in, press Return. (Run it through bash:
# macOS blocks running a script straight from a downloaded disk image.)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP="/Applications/Headset Lock.app"
LABEL="so.zackndr.headsetlock"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

echo ""
echo "Installing Headset Lock..."

# Stop an older copy if one is running.
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
pkill -x HeadsetLock 2>/dev/null || true

# Move an older copy to the Trash, then copy the new one in.
if [[ -e "$APP" ]]; then
  mkdir -p "$HOME/.Trash"
  mv "$APP" "$HOME/.Trash/Headset Lock-old-$(date +%Y-%m-%d-%H%M%S).app"
fi
ditto "$HERE/Headset Lock.app" "$APP"

# Clear the "downloaded from the internet" mark, so macOS does not block it.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

# Start at every login, and now.
mkdir -p "$HOME/Library/LaunchAgents"
cp "$APP/Contents/Resources/$LABEL.plist" "$AGENT"
sleep 1
launchctl bootstrap "$DOMAIN" "$AGENT" 2>/dev/null || open "$APP"

echo ""
echo "Done. Look for the headphones icon at the top right of your screen."
echo "Click Allow when macOS asks about Bluetooth. You can close this window."
echo ""
