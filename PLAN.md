# Headset Lock v2: build plan

Goal: a macOS menu bar app that keeps your headphones on your phone. When you lock the Mac, close the lid or put it to sleep, the app disconnects every Bluetooth audio device (headphones, AirPods, speakers). It never touches keyboards, mice or trackpads. Bluetooth stays on.

Started 2026-10-26. Target: macOS Tahoe, minimum macOS 13. Language: Swift, AppKit, IOBluetooth. No Xcode project, no Hammerspoon, no blueutil, no Homebrew.

## 1. Features

1. Auto-detect audio devices. A device counts as audio when IOBluetoothDevice.deviceClassMajor equals kBluetoothDeviceClassMajorAudio (0x04). Peripheral devices (0x05: Magic Keyboard, Magic Mouse, trackpad) are never disconnected.
2. Exceptions list. The menu lets you mark an audio device as "Never disconnect". Store its address in UserDefaults.
3. Triggers (each has an on/off toggle, all on by default):
   - Lock: DistributedNotificationCenter "com.apple.screenIsLocked"
   - Lid close and sleep: NSWorkspace.willSleepNotification. Disconnect synchronously inside the handler, before it returns.
   - Screen off: NSWorkspace.screensDidSleepNotification
   - Session switch: NSWorkspace.sessionDidResignActiveNotification
4. Guard after wake. On NSWorkspace.didWakeNotification and "com.apple.screenIsUnlocked", open a guard window (default 30 seconds, options 30, 60, 120). During the window, IOBluetoothDevice.register(forConnectNotifications:selector:) catches any audio device that reconnects by itself and disconnects it. After the window closes, connections work as normal.
5. Recheck after lock: check again at 3 and 8 seconds and disconnect any audio device that reconnected.
6. Always running. A LaunchAgent starts the app at login and restarts it after a crash. KeepAlive uses SuccessfulExit = false, so Quit from the menu stops it until the next login.
7. Menu bar icon: headphones symbol. Menu items:
   - Headset Lock (title), Last: <last action and time>
   - Connected audio devices: live list, each with a "Never disconnect" toggle
   - Disconnect on lock / on lid close and sleep / on screen off (toggles)
   - Guard after wake (toggle) and Guard time (30, 60, 120 seconds)
   - Disconnect now
   - Quit Headset Lock
8. Log: append one line per action to ~/Library/Logs/HeadsetLock.log (time, trigger, device, result). Used for testing lid close.

## 2. Folder structure

mac-headset-lock/
  PLAN.md                  this plan
  README.md                how to build, install, use, uninstall
  CLAUDE.md                project rules for Claude
  build.sh                 build, sign, --install, --uninstall
  src/
    main.swift             app entry (NSApplication, accessory policy)
    AppDelegate.swift      status item and menu
    AppModel.swift         shared state for the window
    MainWindow.swift       SwiftUI window: sidebar, stage, inspector (added 2026-10-26)
    BluetoothManager.swift find audio devices, disconnect, exceptions
    EventMonitor.swift     lock, sleep, screen off, wake, unlock events
    ReconnectGuard.swift   guard window and connect notifications
    Settings.swift         UserDefaults keys and defaults
    Logger.swift           writes HeadsetLock.log
  resources/
    Info.plist             bundle id so.zackndr.headsetlock, LSUIElement, NSBluetoothAlwaysUsageDescription
    so.zackndr.headsetlock.plist   LaunchAgent template
  originals/
    hammerspoon-guide.pdf  old guide, never edit

The v1 files (src/main.swift and src/Info.plist from 2026-10-26) were archived outside this repo before the rewrite.

## 3. build.sh

- Check swiftc exists, else print "Run xcode-select --install" and exit 1.
- Compile: swiftc -O -swift-version 5 src/*.swift -framework AppKit -framework IOBluetooth -o "build/Headset Lock.app/Contents/MacOS/HeadsetLock"
- Copy resources/Info.plist into the bundle. Ad-hoc sign: codesign --force --sign -
- --install: stop the running copy, ditto the app to /Applications, copy the LaunchAgent to ~/Library/LaunchAgents, run launchctl bootout (ignore errors) then launchctl bootstrap gui/$(id -u) for the agent.
- --uninstall: launchctl bootout the agent, move the LaunchAgent plist and the app to ~/.Trash (no rm).

## 4. Build order (checklist)

- [x] Move v1 files to the archive folder
- [x] Settings.swift and Logger.swift
- [x] BluetoothManager.swift (list audio devices, disconnect, exceptions)
- [x] EventMonitor.swift (all triggers)
- [x] ReconnectGuard.swift
- [x] AppDelegate.swift and main.swift (menu)
- [x] resources/Info.plist and LaunchAgent plist, plutil -lint passes
- [x] build.sh with --install and --uninstall
- [x] ./build.sh exits 0
- [x] ./build.sh --install exits 0, agent loaded, app running
- [x] README.md and CLAUDE.md updated for v2

## 5. Automatic checks (Claude Code runs these)

1. ./build.sh exits 0 with no errors
2. plutil -lint resources/Info.plist resources/so.zackndr.headsetlock.plist
3. ./build.sh --install exits 0
4. launchctl print gui/$(id -u)/so.zackndr.headsetlock shows the agent
5. pgrep -x HeadsetLock returns a process id

## 6. Manual tests (you do these)

1. Allow Bluetooth when macOS asks.
2. Connect headphones. Lock with Control + Command + Q. Headphones move to the phone. Keyboard and mouse stay connected.
3. Connect headphones. Close the lid for 10 seconds, open it. Headphones stay on the phone. Check ~/Library/Logs/HeadsetLock.log for a "sleep" line.
4. Wake the Mac and wait 30 seconds. Connect headphones from the Bluetooth menu. They connect and stay.
5. Quit from the menu. Log out and in. App is running again.

## 7. Known limits

- Lid close gives the app a short time before sleep. Test 3 confirms whether the disconnect finishes on Tahoe.
- With an external monitor plugged in, closing the lid does not sleep the Mac, so no trigger fires. Out of scope for v2.
- Each rebuild changes the ad-hoc signature, so macOS asks for Bluetooth access again.
- AirPods: also set System Settings > Bluetooth > AirPods (i) > Connect to This Mac > When Last Connected to This Mac.
