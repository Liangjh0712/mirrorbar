import Foundation
import Observation

/// Polls `adb devices`, keeps Wi-Fi adb alive and remembers the phone's IP.
@MainActor
@Observable
final class DeviceMonitor {
    private(set) var devices: [AdbDevice] = []
    private(set) var adbMissing = false

    /// True while mirroring; `adb tcpip` would kill the running session.
    @ObservationIgnored var isBusy: () -> Bool = { false }

    @ObservationIgnored private var lastIPCheck: [String: Date] = [:]
    @ObservationIgnored private var lastConnectAttempt = Date.distantPast
    @ObservationIgnored private var started = false

    var usbDevice: AdbDevice? { devices.first { !$0.isNetwork && $0.isReady } }
    var wifiDevice: AdbDevice? { devices.first { $0.isNetwork && $0.isReady } }
    var anyDevice: AdbDevice? { usbDevice ?? wifiDevice }

    var statusText: String {
        if adbMissing { return "找不到 adb，去设置里改路径" }
        guard let device = anyDevice else { return "手机未连接" }
        let links = [usbDevice != nil ? "USB" : nil, wifiDevice != nil ? "Wi-Fi" : nil]
            .compactMap { $0 }.joined(separator: " + ")
        return "\(device.model.isEmpty ? device.serial : device.model) · \(links)"
    }

    func start() {
        guard !started else { return }
        started = true
        Task {
            await ADB(path: Prefs.current.adbPath).startServer()
            while true {
                await tick()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func refresh() async {
        let prefs = Prefs.current
        adbMissing = !FileManager.default.isExecutableFile(atPath: prefs.adbPath)
        guard !adbMissing else { devices = []; return }
        devices = await ADB(path: prefs.adbPath).devices()
    }

    private func tick() async {
        await refresh()
        let prefs = Prefs.current
        let adb = ADB(path: prefs.adbPath)
        guard !adbMissing else { return }

        // A mirroring session that ended badly (or a crash) may have left phone settings changed.
        if !PhoneSettings.pending.isEmpty, !isBusy(), let device = anyDevice {
            await PhoneSettings.restore(adb: adb, serial: device.serial)
        }

        guard prefs.autoWifi else { return }

        for device in devices where device.isNetwork && device.state == "offline" {
            await adb.disconnect(device.serial)
        }

        if let usb = usbDevice, Date().timeIntervalSince(lastIPCheck[usb.serial] ?? .distantPast) > 60 {
            lastIPCheck[usb.serial] = Date()
            if let ip = await adb.wifiIP(usb.serial) {
                KnownIPs.set(ip, for: usb.serial)
            }
            if !isBusy(), await adb.tcpPort(usb.serial) != "\(ADB.wifiPort)" {
                Log.write("手机 adb 没在监听 \(ADB.wifiPort)，执行 adb tcpip")
                _ = await adb.enableTcpip(usb.serial)
                try? await Task.sleep(for: .seconds(2))
                lastConnectAttempt = .distantPast
            }
        }

        if wifiDevice == nil, Date().timeIntervalSince(lastConnectAttempt) > 10 {
            lastConnectAttempt = Date()
            for ip in Set(KnownIPs.all.values) {
                if await adb.connect("\(ip):\(ADB.wifiPort)") {
                    Log.write("Wi-Fi 已连上 \(ip)")
                    break
                }
            }
            await refresh()
        }
    }
}
