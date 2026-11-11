import Foundation

/// Locks the phone's refresh rate while mirroring and puts it back afterwards.
/// Uses the Xiaomi / HyperOS keys `is_smart_fps` and `user_refresh_rate`;
/// phones without those keys are left alone.
enum RefreshRate {
    struct Saved: Codable {
        var smartFps: String?
        var userRate: String?
    }

    static var pending: Saved? {
        guard let data = UserDefaults.standard.data(forKey: Key.pendingRestore) else { return nil }
        return try? JSONDecoder().decode(Saved.self, from: data)
    }

    private static func setPending(_ saved: Saved?) {
        if let saved, let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: Key.pendingRestore)
        } else {
            UserDefaults.standard.removeObject(forKey: Key.pendingRestore)
        }
    }

    static func target(for fps: Int) -> Int {
        fps <= 60 ? 60 : (fps <= 90 ? 90 : 120)
    }

    static func lock(adb: ADB, serial: String, fps: Int) async {
        if pending == nil {
            let saved = Saved(smartFps: await adb.getSetting(serial, "is_smart_fps"),
                              userRate: await adb.getSetting(serial, "user_refresh_rate"))
            guard saved.smartFps != nil || saved.userRate != nil else { return }
            // Saved before changing anything, so a crash still leaves a way back.
            setPending(saved)
        }
        let rate = target(for: fps)
        await adb.putSetting(serial, "is_smart_fps", "0")
        await adb.putSetting(serial, "user_refresh_rate", "\(rate)")
        Log.write("手机刷新率锁到 \(rate)Hz")
    }

    static func restore(adb: ADB, serial: String) async {
        guard let saved = pending else { return }
        if let value = saved.smartFps { await adb.putSetting(serial, "is_smart_fps", value) }
        if let value = saved.userRate { await adb.putSetting(serial, "user_refresh_rate", value) }
        setPending(nil)
        Log.write("手机刷新率恢复：is_smart_fps=\(saved.smartFps ?? "-") user_refresh_rate=\(saved.userRate ?? "-")")
    }

    /// Used while the app quits, when there is no time for async work.
    static func restoreSync(adbPath: String, serial: String) {
        guard let saved = pending else { return }
        for (key, value) in [("is_smart_fps", saved.smartFps), ("user_refresh_rate", saved.userRate)] {
            guard let value else { continue }
            _ = Shell.runSync(adbPath, ["-s", serial, "shell", "settings put system \(key) \(value)"], timeout: 3)
        }
        setPending(nil)
    }
}
