import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppState {
    static let shared = AppState()

    let monitor: DeviceMonitor
    let session: MirrorSession
    private var toolbar: ToolbarController?

    private init() {
        Prefs.registerDefaults()
        monitor = DeviceMonitor()
        session = MirrorSession(monitor: monitor)
        monitor.isBusy = { [weak session] in session?.isActive ?? false }
        // A scrcpy left over from a crashed run would fight the new one for the phone.
        _ = Shell.runSync("/usr/bin/pkill", ["-f", "window-title=Mirrorbar"], timeout: 3)
        monitor.start()
        toolbar = ToolbarController(session: session)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var sigterm: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `pkill Mirrorbar` should still stop scrcpy and restore the refresh rate.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        sigterm = source
    }

    /// mirrorbar://start | stop | toggle, plus one URL per toolbar button (mirrorbar://back …),
    /// for Shortcuts, Raycast or a hotkey tool.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            let session = AppState.shared.session
            for url in urls where url.scheme == "mirrorbar" {
                switch url.host {
                case "start": session.start()
                case "stop": session.stop()
                case "toggle": session.toggle()
                default:
                    if let action = PhoneAction(rawValue: url.host ?? "") {
                        Task { _ = await session.perform(action) }
                    } else {
                        Log.write("未处理的链接：\(url)")
                    }
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppState.shared.session.shutdown() }
    }
}

@main
struct MirrorbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(monitor: state.monitor, session: state.session)
        } label: {
            MenuIcon(monitor: state.monitor, session: state.session)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(session: state.session)
        }
    }
}

struct MenuIcon: View {
    let monitor: DeviceMonitor
    let session: MirrorSession

    var body: some View {
        if session.isActive {
            Image(systemName: "iphone.radiowaves.left.and.right")
        } else if monitor.anyDevice != nil {
            Image(systemName: "iphone")
        } else {
            Image(systemName: "iphone.slash")
        }
    }
}

struct MenuContent: View {
    let monitor: DeviceMonitor
    let session: MirrorSession

    @AppStorage(Key.alwaysOnTop) private var alwaysOnTop = false
    @AppStorage(Key.turnScreenOff) private var turnScreenOff = true
    @AppStorage(Key.audioMode) private var audioMode = AudioMode.mac.rawValue
    @AppStorage(Key.showToolbar) private var showToolbar = true

    var body: some View {
        Text(monitor.statusText)
        if let status = session.statusText {
            Text(status)
        }
        if let error = session.lastError, !session.isActive {
            Text("⚠︎ \(error)")
        }

        Button(session.isActive ? "停止镜像" : "开始镜像") { session.toggle() }
            .keyboardShortcut("m")
            .disabled(!session.isActive && monitor.anyDevice == nil)

        Divider()

        Toggle("显示操作栏", isOn: $showToolbar)
        Toggle("窗口置顶", isOn: restarting($alwaysOnTop))
        Toggle("手机息屏（镜像照常）", isOn: restarting($turnScreenOff))
        Picker("声音", selection: restarting($audioMode)) {
            ForEach(AudioMode.allCases) { Text($0.label).tag($0.rawValue) }
        }

        Divider()

        SettingsLink { Text("设置…") }
            .keyboardShortcut(",")
        Button("打开日志") { NSWorkspace.shared.open(Log.url) }
        Button("退出 Mirrorbar") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// Menu toggles take effect right away by restarting scrcpy.
    private func restarting<T>(_ binding: Binding<T>) -> Binding<T> {
        Binding(get: { binding.wrappedValue }, set: { value in
            binding.wrappedValue = value
            session.restartIfActive()
        })
    }
}

struct SettingsView: View {
    let session: MirrorSession

    @AppStorage(Key.fps) private var fps = 90
    @AppStorage(Key.bitrateUSB) private var bitrateUSB = 24
    @AppStorage(Key.bitrateWifi) private var bitrateWifi = 12
    @AppStorage(Key.videoCodec) private var videoCodec = VideoCodec.h265.rawValue
    @AppStorage(Key.maxSize) private var maxSize = 0
    @AppStorage(Key.preferUSB) private var preferUSB = true
    @AppStorage(Key.autoWifi) private var autoWifi = true
    @AppStorage(Key.lockRefreshRate) private var lockRefreshRate = true
    @AppStorage(Key.autoReconnect) private var autoReconnect = true
    @AppStorage(Key.stayAwake) private var stayAwake = true
    @AppStorage(Key.keyboardMode) private var keyboardMode = KeyboardMode.sdk.rawValue
    @AppStorage(Key.screenName) private var screenName = ""
    @AppStorage(Key.extraArgs) private var extraArgs = ""
    @AppStorage(Key.scrcpyPath) private var scrcpyPath = ""
    @AppStorage(Key.adbPath) private var adbPath = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("画面") {
                Picker("帧率", selection: $fps) {
                    ForEach([60, 90, 120], id: \.self) { Text("\($0) fps").tag($0) }
                }
                Picker("编码", selection: $videoCodec) {
                    ForEach(VideoCodec.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Stepper("USB 码率上限：\(bitrateUSB) Mbps", value: $bitrateUSB, in: 4...60, step: 2)
                Stepper("Wi-Fi 码率上限：\(bitrateWifi) Mbps", value: $bitrateWifi, in: 2...40, step: 2)
                Picker("分辨率（最长边）", selection: $maxSize) {
                    Text("原生").tag(0)
                    Text("1920").tag(1920)
                    Text("1440").tag(1440)
                    Text("1080").tag(1080)
                }
                Picker("显示器", selection: $screenName) {
                    Text("自动（选刷新率够高的屏）").tag("")
                    ForEach(Screens.names, id: \.self) { Text($0).tag($0) }
                }
                Toggle("镜像时锁定手机刷新率（小米），结束后恢复", isOn: $lockRefreshRate)
            }
            Section("连接") {
                Picker("优先连接", selection: $preferUSB) {
                    Text("USB").tag(true)
                    Text("Wi-Fi").tag(false)
                }
                Toggle("插 USB 时自动开启无线 adb，拔线后走 Wi-Fi", isOn: $autoWifi)
                Toggle("断线自动重连", isOn: $autoReconnect)
                Toggle("镜像时手机保持唤醒", isOn: $stayAwake)
            }
            Section("输入") {
                Picker("键盘", selection: $keyboardMode) {
                    ForEach(KeyboardMode.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Text("输中文：在 Mac 上复制，到镜像窗口按 ⌘V 粘贴。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("高级") {
                TextField("scrcpy 路径", text: $scrcpyPath)
                TextField("adb 路径", text: $adbPath)
                TextField("额外 scrcpy 参数", text: $extraArgs)
                Toggle("登录时启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            }
            if session.isActive {
                Button("应用并重启镜像") { session.restartIfActive() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onAppear { NSApp.activate() }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.write("登录时启动设置失败：\(error.localizedDescription)")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
