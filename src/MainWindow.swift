// MainWindow: the app window. Sidebar with audio devices, a stage with the
// current state, and an inspector with grouped settings. Liquid Glass on macOS 26.

import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 640),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Headset Lock"
            w.subtitle = "Running"
            w.titlebarAppearsTransparent = true
            w.toolbar = NSToolbar(identifier: "main")
            w.toolbarStyle = .unified
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 900, height: 560)
            w.contentView = NSHostingView(rootView: MainView(model: .shared))
            w.delegate = self
            w.center()
            w.setFrameAutosaveName("HeadsetLockMain")
            window = w
        }
        AppModel.shared.startRefreshing()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        AppModel.shared.stopRefreshing()
    }
}

// MARK: Glass

extension View {
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat = 14) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

// MARK: Root

struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var selection: String?

    var body: some View {
        NavigationSplitView {
            Sidebar(model: model, selection: $selection)
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
        } detail: {
            HStack(spacing: 0) {
                Stage(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Inspector(model: model, selected: model.devices.first { $0.id == selection })
                    .frame(width: 310)
            }
        }
        .onAppear { if selection == nil { selection = model.devices.first?.id } }
    }
}

// MARK: Sidebar

struct Sidebar: View {
    @ObservedObject var model: AppModel
    @Binding var selection: String?

    var body: some View {
        List(selection: $selection) {
            Section("Audio devices") {
                if model.devices.isEmpty {
                    Text("No paired audio devices")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.devices) { device in
                    HStack(spacing: 10) {
                        Image(systemName: "headphones")
                            .frame(width: 20)
                            .foregroundStyle(device.connected ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(device.name)
                            Text(device.connected ? "Connected" : "Not connected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if device.never {
                            Image(systemName: "pin.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .help("Never disconnect")
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(device.id)
                }
            }
            Section("Never touched") {
                Label("Keyboards, mice, trackpads", systemImage: "keyboard")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Link(destination: Creator.link) {
                Label("Created by \(Creator.name)", systemImage: "person.crop.circle")
                    .font(.caption)
            }
            .help("Open \(Creator.name) on LinkedIn")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
    }
}

// MARK: Stage

struct Stage: View {
    @ObservedObject var model: AppModel

    private var headline: String {
        switch model.connectedCount {
        case 0: return "No audio connected"
        case 1: return "1 audio device connected"
        default: return "\(model.connectedCount) audio devices connected"
        }
    }

    private var chipText: String {
        if model.guardLeft > 0 { return "Guard open: \(model.guardLeft) s" }
        if model.watchMinutesLeft > 0 { return "Waiting for your phone to let go (\(model.watchMinutesLeft) min)" }
        return "After wake: \(model.afterWake.title)"
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.55, green: 0.75, blue: 0.98),
                                    Color(red: 0.10, green: 0.36, blue: 0.85),
                                    Color(red: 0.05, green: 0.18, blue: 0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 64, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.08)],
                                             startPoint: .top, endPoint: .bottom))
                    Image(systemName: "headphones")
                        .font(.system(size: 120, weight: .light))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                }
                .frame(width: 260, height: 260)
                .glassPanel(cornerRadius: 64)
                .shadow(color: .black.opacity(0.25), radius: 30, y: 16)

                VStack(spacing: 6) {
                    Text(headline)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Last: \(model.lastAction)")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: 420)
                }

                Button {
                    model.disconnectAll()
                    model.refresh()
                } label: {
                    Label("Disconnect now", systemImage: "bolt.horizontal.circle")
                        .padding(.horizontal, 8)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("d", modifiers: .command)
                Spacer()

                HStack {
                    StatusChip(text: chipText, systemImage: "sunrise")
                    Spacer()
                    StatusChip(text: "Bluetooth stays on", systemImage: "antenna.radiowaves.left.and.right")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
    }
}

struct StatusChip: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassPanel(cornerRadius: 10)
    }
}

// MARK: Inspector

struct Inspector: View {
    @ObservedObject var model: AppModel
    let selected: AudioDevice?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                InspectorSection(title: "Disconnect on") {
                    SwitchRow(title: "Lock", systemImage: "lock", isOn: $model.onLock)
                    SwitchRow(title: "Lid close and sleep", systemImage: "laptopcomputer", isOn: $model.onSleep)
                    SwitchRow(title: "Screen off", systemImage: "display", isOn: $model.onScreenOff)
                    SwitchRow(title: "User switch", systemImage: "person.2", isOn: $model.onSessionSwitch, last: true)
                }

                InspectorSection(title: "After wake") {
                    InspectorRow(title: "Earbuds", systemImage: "sunrise") {
                        Picker("After wake", selection: $model.afterWake) {
                            ForEach(AfterWake.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                    SwitchRow(title: "Take back from phone", systemImage: "arrow.uturn.backward",
                              isOn: $model.takeBack)
                        .disabled(model.afterWake != .reconnect)
                    InspectorRow(title: "Guard time", systemImage: "timer", last: true) {
                        Picker("Guard time", selection: $model.guardSeconds) {
                            ForEach(Settings.guardChoices, id: \.self) { Text("\($0) s").tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                        .disabled(model.afterWake != .keepOff)
                    }
                }

                InspectorSection(title: "Selected device") {
                    if let device = selected {
                        InspectorRow(title: device.name, systemImage: "headphones") {
                            Text(device.connected ? "Connected" : "Not connected")
                                .foregroundStyle(.secondary)
                        }
                        SwitchRow(title: "Never disconnect", systemImage: "pin",
                                  isOn: Binding(get: { device.never },
                                                set: { model.setNever(device.id, $0) }))
                        InspectorRow(title: "Disconnect", systemImage: "xmark.circle", last: true) {
                            Button("Disconnect") {
                                model.disconnectDevice(device.id)
                                model.refresh()
                            }
                            .disabled(!device.connected || device.never)
                        }
                    } else {
                        InspectorRow(title: "Pick a device in the sidebar", systemImage: "sidebar.left", last: true) {
                            EmptyView()
                        }
                    }
                }

                InspectorSection(title: "Log") {
                    InspectorRow(title: "HeadsetLock.log", systemImage: "doc.text", last: true) {
                        Button("Open") { NSWorkspace.shared.open(Logger.url) }
                    }
                }
            }
            .padding(16)
        }
        .background(.ultraThinMaterial)
    }
}

struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) { content }
                .glassPanel(cornerRadius: 14)
        }
    }
}

struct InspectorRow<Accessory: View>: View {
    let title: String
    let systemImage: String
    var last = false
    @ViewBuilder let accessory: Accessory

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 8)
                accessory
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 38)
            if !last { Divider().padding(.leading, 40) }
        }
    }
}

struct SwitchRow: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool
    var last = false

    var body: some View {
        InspectorRow(title: title, systemImage: systemImage, last: last) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}
