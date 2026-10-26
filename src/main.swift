// Headset Lock v2: disconnects Bluetooth audio devices when the Mac locks or sleeps.
// Bluetooth stays on. Keyboards, mice and trackpads are never touched.

import AppKit

// Run only one copy. Exit 0 so the LaunchAgent does not restart this one.
let me = ProcessInfo.processInfo.processIdentifier
let others = NSWorkspace.shared.runningApplications.filter {
    $0.bundleIdentifier == Bundle.main.bundleIdentifier && $0.processIdentifier != me
}
if Bundle.main.bundleIdentifier != nil && !others.isEmpty {
    exit(0)
}

// Top-level code runs on the main thread.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
