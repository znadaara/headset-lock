#!/bin/bash
# Builds Headset Lock.app from src/.
# Run: ./build.sh   or   ./build.sh --install   or   ./build.sh --uninstall   or   ./build.sh --dmg
set -euo pipefail
cd "$(dirname "$0")"

LABEL="so.zackndr.headsetlock"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
INSTALLED="/Applications/Headset Lock.app"
DOMAIN="gui/$(id -u)"

if [[ "${1:-}" == "--uninstall" ]]; then
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  pkill -x HeadsetLock 2>/dev/null || true
  stamp=$(date +%Y-%m-%d-%H%M%S)
  [[ -e "$AGENT" ]] && mv "$AGENT" "$HOME/.Trash/$LABEL-$stamp.plist"
  [[ -e "$INSTALLED" ]] && mv "$INSTALLED" "$HOME/.Trash/Headset Lock-$stamp.app"
  echo "Uninstalled. The app and LaunchAgent are in the Trash."
  exit 0
fi

if ! command -v swiftc >/dev/null 2>&1; then
  echo "Run xcode-select --install"
  exit 1
fi

APP="build/Headset Lock.app"
# Scratch space for in-between files, removed when the script ends.
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

BIN="$APP/Contents/MacOS/HeadsetLock"

echo "Compiling..."
if [[ "${1:-}" == "--dmg" ]]; then
  # Universal app for sharing: Apple Silicon and Intel.
  for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" src/*.swift \
      -framework AppKit -framework IOBluetooth \
      -o "$WORK/HeadsetLock-$arch"
  done
  lipo -create "$WORK/HeadsetLock-arm64" "$WORK/HeadsetLock-x86_64" -output "$BIN"
else
  swiftc -O -swift-version 5 src/*.swift \
    -framework AppKit -framework IOBluetooth \
    -o "$BIN"
fi

cp resources/Info.plist "$APP/Contents/Info.plist"
# The app copies this into ~/Library/LaunchAgents on first launch from /Applications.
cp "resources/$LABEL.plist" "$APP/Contents/Resources/$LABEL.plist"
cp resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# macOS remembers Bluetooth access per signature. An ad-hoc signature changes on
# every build, so macOS asks again. A certificate in your keychain keeps it stable.
# Other Macs do not know that certificate and refuse the app with no way around it,
# so the DMG for sharing is always signed ad-hoc (users get Open Anyway).
SIGN_ID="${HEADSET_LOCK_SIGN_ID:-Headset Lock Signing}"
if [[ "${1:-}" != "--dmg" ]] && security find-identity -p codesigning | grep -q "\"$SIGN_ID\""; then
  codesign --force --sign "$SIGN_ID" "$APP"
  echo "Signed with: $SIGN_ID"
else
  codesign --force --sign - "$APP"
  if [[ "${1:-}" == "--dmg" ]]; then
    echo "Signed ad-hoc for sharing."
  else
    echo "Signed ad-hoc. macOS asks for Bluetooth again after each build. See README, Stop the Bluetooth prompt."
  fi
fi
echo "Built: $APP"

if [[ "${1:-}" == "--install" ]]; then
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  pkill -x HeadsetLock 2>/dev/null || true
  ditto "$APP" "$INSTALLED"
  mkdir -p "$HOME/Library/LaunchAgents"
  cp resources/$LABEL.plist "$AGENT"
  # bootout can take a moment to finish, so retry bootstrap a few times.
  for attempt in 1 2 3 4 5; do
    if launchctl bootstrap "$DOMAIN" "$AGENT" 2>/dev/null; then
      break
    fi
    if [[ $attempt == 5 ]]; then
      echo "launchctl bootstrap failed."
      exit 1
    fi
    sleep 1
  done
  echo "Installed to /Applications and loaded the LaunchAgent. Look for the headphones icon in the menu bar."
fi

if [[ "${1:-}" == "--dmg" ]]; then
  VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" resources/Info.plist)
  STAGE="$WORK/dmg"
  DMG="build/headset-lock-$VERSION.dmg"
  mkdir -p "$STAGE"
  ditto "$APP" "$STAGE/Headset Lock.app"
  ln -sfn /Applications "$STAGE/Applications"
  cp resources/dmg-read-me-first.txt "$STAGE/Read Me First.txt"
  cp resources/install.command "$STAGE/Install Headset Lock.command"
  hdiutil create -volname "Headset Lock $VERSION" -srcfolder "$STAGE" -format UDZO -ov "$DMG" >/dev/null
  echo "DMG: $DMG ($(lipo -archs "$BIN"))"
fi
