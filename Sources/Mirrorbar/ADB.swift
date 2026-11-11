import Foundation

struct AdbDevice: Hashable, Identifiable {
    let serial: String
    let state: String
    let model: String

    var id: String { serial }
    var isNetwork: Bool { serial.contains(":") || serial.contains("._adb") }
    var isReady: Bool { state == "device" }
    var transport: String { isNetwork ? "Wi-Fi" : "USB" }
}

struct ADB {
    let path: String

    static let wifiPort = 5555

    func startServer() async {
        _ = await Shell.run(path, ["start-server"], timeout: 10)
    }

    func devices() async -> [AdbDevice] {
        let result = await Shell.run(path, ["devices", "-l"], timeout: 5)
        return result.output.split(separator: "\n").dropFirst().compactMap { line in
            if line.hasPrefix("*") { return nil }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 2 else { return nil }
            let model = parts.first { $0.hasPrefix("model:") }.map { String($0.dropFirst(6)) } ?? ""
            return AdbDevice(serial: parts[0], state: parts[1], model: model)
        }
    }

    func shell(_ serial: String, _ command: String, timeout: TimeInterval = 5) async -> ShellResult {
        await Shell.run(path, ["-s", serial, "shell", command], timeout: timeout)
    }

    /// IPv4 address of wlan0, read over the current connection (works over USB).
    func wifiIP(_ serial: String) async -> String? {
        let output = await shell(serial, "ip -f inet addr show wlan0").output
        guard let range = output.range(of: #"inet \d+\.\d+\.\d+\.\d+"#, options: .regularExpression)
        else { return nil }
        return String(output[range].dropFirst(5))
    }

    func tcpPort(_ serial: String) async -> String {
        await shell(serial, "getprop service.adb.tcp.port").output
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Restarts adbd on the phone in TCP mode. Drops every adb connection to it.
    func enableTcpip(_ serial: String) async -> Bool {
        await Shell.run(path, ["-s", serial, "tcpip", "\(Self.wifiPort)"], timeout: 10).ok
    }

    func connect(_ address: String) async -> Bool {
        let output = await Shell.run(path, ["connect", address], timeout: 5).output
        return output.contains("connected to")
    }

    func disconnect(_ address: String) async {
        _ = await Shell.run(path, ["disconnect", address], timeout: 5)
    }

    func getSetting(_ serial: String, _ namespace: String = "system", _ key: String) async -> String? {
        let value = await shell(serial, "settings get \(namespace) \(key)").output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value == "null" ? nil : value
    }

    func putSetting(_ serial: String, _ namespace: String = "system", _ key: String, _ value: String) async {
        _ = await shell(serial, "settings put \(namespace) \(key) \(value)")
    }

    func deleteSetting(_ serial: String, _ namespace: String, _ key: String) async {
        _ = await shell(serial, "settings delete \(namespace) \(key)")
    }

    /// Current orientation and the screen size as apps see it (swapped in landscape).
    func viewport(_ serial: String) async -> (landscape: Bool, width: Int, height: Int)? {
        let output = await shell(serial, "dumpsys input | grep -m1 'Viewport INTERNAL'").output
        guard let o = output.range(of: #"orientation=\d"#, options: .regularExpression),
              let f = output.range(of: #"logicalFrame=\[0, 0, \d+, \d+\]"#, options: .regularExpression)
        else { return nil }
        let landscape = ["1", "3"].contains(String(output[o].suffix(1)))
        let numbers = output[f].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard numbers.count == 4 else { return nil }
        return (landscape, numbers[2], numbers[3])
    }

    func isLandscape(_ serial: String) async -> Bool {
        await viewport(serial)?.landscape ?? false
    }

    /// Physical screen size in pixels, e.g. 1200x2608.
    func screenSize(_ serial: String) async -> (width: Int, height: Int)? {
        let output = await shell(serial, "wm size").output
        guard let line = output.split(separator: "\n").last(where: { $0.contains("size:") }),
              let sizeText = line.split(separator: ":").last
        else { return nil }
        let numbers = sizeText.trimmingCharacters(in: .whitespaces).split(separator: "x").compactMap { Int($0) }
        guard numbers.count == 2 else { return nil }
        return (numbers[0], numbers[1])
    }
}
