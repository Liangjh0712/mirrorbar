import Foundation

/// Phone settings Mirrorbar changes while mirroring (refresh rate, rotation).
/// The original value is saved before the first change and put back when mirroring
/// ends; after a crash it is put back the next time the phone shows up.
enum PhoneSettings {
    /// "namespace/key" → original value; "" means the setting did not exist.
    static var pending: [String: String] {
        UserDefaults.standard.dictionary(forKey: Key.pendingRestore) as? [String: String] ?? [:]
    }

    private static func save(_ map: [String: String]) {
        if map.isEmpty {
            UserDefaults.standard.removeObject(forKey: Key.pendingRestore)
        } else {
            UserDefaults.standard.set(map, forKey: Key.pendingRestore)
        }
    }

    static func override(adb: ADB, serial: String, namespace: String = "system",
                         key: String, value: String) async {
        let id = "\(namespace)/\(key)"
        var map = pending
        if map[id] == nil {
            map[id] = await adb.getSetting(serial, namespace, key) ?? ""
            save(map)
        }
        await adb.putSetting(serial, namespace, key, value)
    }

    static func restore(adb: ADB, serial: String) async {
        let map = pending
        guard !map.isEmpty else { return }
        for (id, value) in map {
            let parts = id.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            if value.isEmpty {
                await adb.deleteSetting(serial, parts[0], parts[1])
            } else {
                await adb.putSetting(serial, parts[0], parts[1], value)
            }
        }
        save([:])
        Log.write("手机设置已恢复：\(map.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " "))")
    }

    /// Used while the app quits, when there is no time for async work.
    static func restoreSync(adbPath: String, serial: String) {
        for (id, value) in pending {
            let parts = id.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let command = value.isEmpty
                ? "settings delete \(parts[0]) \(parts[1])"
                : "settings put \(parts[0]) \(parts[1]) \(value)"
            _ = Shell.runSync(adbPath, ["-s", serial, "shell", command], timeout: 3)
        }
        save([:])
    }

    // MARK: - Refresh rate (Xiaomi / HyperOS)

    static func lockRefreshRate(adb: ADB, serial: String, fps: Int) async {
        let smart = await adb.getSetting(serial, "system", "is_smart_fps")
        let rate = await adb.getSetting(serial, "system", "user_refresh_rate")
        guard smart != nil || rate != nil || pending["system/is_smart_fps"] != nil else { return }
        let target = fps <= 60 ? 60 : (fps <= 90 ? 90 : 120)
        await override(adb: adb, serial: serial, key: "is_smart_fps", value: "0")
        await override(adb: adb, serial: serial, key: "user_refresh_rate", value: "\(target)")
        Log.write("手机刷新率锁到 \(target)Hz")
    }

    // MARK: - Rotation

    /// Flips between portrait and landscape with auto-rotate turned off.
    /// Apps that fix their own orientation ignore this.
    static func toggleRotation(adb: ADB, serial: String) async {
        let landscape = await adb.isLandscape(serial)
        await override(adb: adb, serial: serial, key: "accelerometer_rotation", value: "0")
        await override(adb: adb, serial: serial, key: "user_rotation", value: landscape ? "0" : "1")
        Log.write("切到\(landscape ? "竖屏" : "横屏")")
    }
}
