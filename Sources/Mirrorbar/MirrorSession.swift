import AppKit
import Observation

/// One scrcpy process at a time, restarted on disconnect.
@MainActor
@Observable
final class MirrorSession {
    enum State: Equatable {
        case idle
        case starting
        case running(transport: String)
        case reconnecting
    }

    private(set) var state: State = .idle
    private(set) var fps: Int?
    private(set) var lastError: String?

    @ObservationIgnored private let monitor: DeviceMonitor
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var serial: String?
    @ObservationIgnored private var userStopped = false
    @ObservationIgnored private var pendingRestart = false
    @ObservationIgnored private var retries = 0
    @ObservationIgnored private var launchedAt = Date.distantPast
    @ObservationIgnored private var lastErrorLine: String?
    @ObservationIgnored private var lastFpsLog = Date.distantPast

    private static let maxRetries = 8

    init(monitor: DeviceMonitor) {
        self.monitor = monitor
    }

    var isActive: Bool { state != .idle }

    var statusText: String? {
        switch state {
        case .idle: nil
        case .starting: "正在启动镜像…"
        case .reconnecting: "连接断了，正在重连…"
        case .running(let transport):
            "镜像中 · \(transport)" + (fps.map { " · \($0) fps" } ?? "")
        }
    }

    func toggle() {
        if isActive { stop() } else { start() }
    }

    func start() {
        guard !isActive else { return }
        userStopped = false
        retries = 0
        lastError = nil
        Task { await launch() }
    }

    func stop() {
        userStopped = true
        if let process {
            process.terminate()
        } else {
            finish()
        }
    }

    /// Applies changed options by restarting scrcpy, keeping the refresh rate locked.
    func restartIfActive() {
        guard let process else { return }
        pendingRestart = true
        process.terminate()
    }

    /// Called when the app quits.
    func shutdown() {
        userStopped = true
        process?.terminate()
        process?.waitUntilExit()
        let adbPath = Prefs.current.adbPath
        if let device = monitor.anyDevice ?? serial.map({ AdbDevice(serial: $0, state: "device", model: "") }) {
            RefreshRate.restoreSync(adbPath: adbPath, serial: device.serial)
        }
    }

    // MARK: - Launch

    private func pickDevice() -> AdbDevice? {
        Prefs.current.preferUSB
            ? (monitor.usbDevice ?? monitor.wifiDevice)
            : (monitor.wifiDevice ?? monitor.usbDevice)
    }

    private func launch() async {
        state = .starting
        let prefs = Prefs.current
        guard FileManager.default.isExecutableFile(atPath: prefs.scrcpyPath) else {
            fail("找不到 scrcpy：\(prefs.scrcpyPath)")
            return
        }
        await monitor.refresh()
        guard let device = pickDevice() else {
            if retries > 0 {
                retryOrFail("没有找到手机，先插 USB 或连上 Wi-Fi")
            } else {
                fail("没有找到手机，先插 USB 或连上 Wi-Fi")
            }
            return
        }
        guard !userStopped else { finish(); return }

        let adb = ADB(path: prefs.adbPath)
        if prefs.lockRefreshRate {
            await RefreshRate.lock(adb: adb, serial: device.serial, fps: prefs.fps)
        }
        let size = await adb.screenSize(device.serial)
        let landscape = await adb.isLandscape(device.serial)
        let frame = Screens.windowFrame(fps: prefs.fps, preferredName: prefs.screenName,
                                        device: size, landscape: landscape)

        var args = [
            "-s", device.serial,
            "--max-fps=\(prefs.fps)",
            "--video-bit-rate=\(prefs.bitrate)M",
            "--window-title=Mirrorbar",
            "--print-fps",
            "--disable-screensaver",
            "--keyboard=\(prefs.keyboardMode.rawValue)",
        ]
        if prefs.maxSize > 0 { args.append("--max-size=\(prefs.maxSize)") }
        switch prefs.audioMode {
        case .mac: args += ["--audio-codec=opus", "--audio-buffer=50"]
        case .both: args += ["--audio-codec=opus", "--audio-buffer=50", "--audio-dup", "--audio-source=playback"]
        case .off: args.append("--no-audio")
        }
        if prefs.alwaysOnTop { args.append("--always-on-top") }
        if prefs.turnScreenOff { args.append("--turn-screen-off") }
        if prefs.stayAwake { args.append("--stay-awake") }
        if let frame {
            args += ["--window-x=\(frame.x)", "--window-y=\(frame.y)",
                     "--window-width=\(frame.width)", "--window-height=\(frame.height)"]
        }
        args += prefs.extraArgs.split(separator: " ").map(String.init)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: prefs.scrcpyPath)
        process.arguments = args
        var environment = ProcessInfo.processInfo.environment
        environment["ADB"] = prefs.adbPath
        process.environment = environment

        // scrcpy block-buffers stdout into a pipe, so the fps lines would never arrive.
        // A pseudo-terminal makes it line-buffered.
        var master: Int32 = -1
        var slave: Int32 = -1
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            fail("无法创建伪终端")
            return
        }
        let terminal = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
        process.standardOutput = terminal
        process.standardError = terminal
        process.standardInput = FileHandle.nullDevice
        process.terminationHandler = { [weak self] finished in
            let code = finished.terminationStatus
            Task { @MainActor in self?.handleExit(code: code) }
        }

        Log.write("启动 scrcpy：\(args.joined(separator: " "))")
        Log.write("显示器：\(Screens.describe())")
        do {
            try process.run()
        } catch {
            close(master)
            fail("scrcpy 启动失败：\(error.localizedDescription)")
            return
        }
        // The child holds its own copy; closing ours lets the master see EOF when scrcpy exits.
        try? terminal.close()
        // A plain thread owns the master end and reads until scrcpy closes the terminal.
        Thread.detachNewThread { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = read(master, &buffer, buffer.count)
                if count <= 0 { break }
                let text = String(decoding: buffer[0..<count], as: UTF8.self)
                Task { @MainActor in self?.consume(text) }
            }
            close(master)
        }
        self.process = process
        self.serial = device.serial
        launchedAt = Date()
        lastErrorLine = nil
        fps = nil
        state = .running(transport: device.transport)
    }

    private func consume(_ text: String) {
        // The terminal adds color codes and a window-title sequence; drop them.
        let clean = text
            .replacingOccurrences(of: "\u{1B}\\][^\u{07}]*\u{07}", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
        for raw in clean.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if let range = line.range(of: #"\d+ fps"#, options: .regularExpression),
               let value = Int(line[range].split(separator: " ")[0]) {
                fps = value
                if Date().timeIntervalSince(lastFpsLog) > 30 {
                    lastFpsLog = Date()
                    Log.write("帧率 \(value) fps")
                }
                continue
            }
            Log.write("scrcpy | \(line)")
            if line.hasPrefix("ERROR") { lastErrorLine = line }
        }
    }

    private func handleExit(code: Int32) {
        process = nil
        fps = nil
        Log.write("scrcpy 退出，code=\(code)")

        if pendingRestart {
            pendingRestart = false
            Task { await launch() }
            return
        }
        // 0 = window closed by the user.
        if userStopped || code == 0 {
            finish()
            return
        }
        if Date().timeIntervalSince(launchedAt) > 30 { retries = 0 }
        retryOrFail(lastErrorLine ?? "scrcpy 异常退出（code \(code)）")
    }

    private func retryOrFail(_ message: String) {
        guard Prefs.current.autoReconnect, retries < Self.maxRetries else {
            fail(message)
            return
        }
        retries += 1
        state = .reconnecting
        Task {
            try? await Task.sleep(for: .seconds(3))
            guard !userStopped else { finish(); return }
            await launch()
        }
    }

    private func fail(_ message: String) {
        lastError = message
        Log.write("错误：\(message)")
        finish()
    }

    private func finish() {
        state = .idle
        fps = nil
        let adb = ADB(path: Prefs.current.adbPath)
        let fallback = serial
        Task {
            await monitor.refresh()
            if let target = monitor.anyDevice?.serial ?? fallback {
                await RefreshRate.restore(adb: adb, serial: target)
            }
        }
    }
}
