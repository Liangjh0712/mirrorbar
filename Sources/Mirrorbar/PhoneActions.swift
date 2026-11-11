import AppKit

/// Raw values double as URL hosts: mirrorbar://back, mirrorbar://swipe-up …
enum PhoneAction: String, CaseIterable, Identifiable {
    case back, home, recents
    case rotate, notifications, screenshot
    case volumeUp = "volume-up", volumeDown = "volume-down", screen, power
    case swipeUp = "swipe-up", swipeDown = "swipe-down"

    var id: Self { self }

    static let groups: [[PhoneAction]] = [
        [.back, .home, .recents],
        [.rotate, .notifications, .screenshot],
        [.volumeUp, .volumeDown, .screen, .power],
        [.swipeUp, .swipeDown],
    ]

    var symbol: String {
        switch self {
        case .back: "arrowtriangle.backward"
        case .home: "circle"
        case .recents: "square"
        case .rotate: "rectangle.portrait.rotate"
        case .notifications: "arrow.down.to.line"
        case .screenshot: "camera.viewfinder"
        case .volumeUp: "speaker.plus"
        case .volumeDown: "speaker.minus"
        case .screen: "moon"
        case .power: "power"
        case .swipeUp: "chevron.up"
        case .swipeDown: "chevron.down"
        }
    }

    /// Tooltip; the shortcut is scrcpy's own, active while the mirror window is in front.
    var help: String {
        switch self {
        case .back: "返回（⌘B 或右键）"
        case .home: "主页（⌘H 或中键）"
        case .recents: "后台（⌘S）"
        case .rotate: "横竖屏切换（⌘R）"
        case .notifications: "下拉通知栏（⌘N）"
        case .screenshot: "截图：存到桌面并复制"
        case .volumeUp: "音量 +（⌘↑）"
        case .volumeDown: "音量 −（⌘↓）"
        case .screen: "手机息屏 / 亮屏（镜像照常）"
        case .power: "锁屏 / 亮屏（⌘P）"
        case .swipeUp: "上滑：下一条"
        case .swipeDown: "下滑：上一条"
        }
    }
}

@MainActor
enum PhoneActions {
    static func perform(_ action: PhoneAction, serial: String) async -> Bool {
        let adb = ADB(path: Prefs.current.adbPath)
        switch action {
        case .back: return await key(adb, serial, 4)
        case .home: return await key(adb, serial, 3)
        case .recents: return await key(adb, serial, 187)
        case .volumeUp: return await key(adb, serial, 24)
        case .volumeDown: return await key(adb, serial, 25)
        case .power: return await key(adb, serial, 26)
        case .screen: return false  // handled by MirrorSession: needs a scrcpy restart
        case .notifications:
            return await adb.shell(serial, "cmd statusbar expand-notifications").ok
        case .rotate:
            await PhoneSettings.toggleRotation(adb: adb, serial: serial)
            return true
        case .screenshot:
            return await screenshot(adb, serial)
        case .swipeUp, .swipeDown:
            return await swipe(adb, serial, up: action == .swipeUp)
        }
    }

    private static func key(_ adb: ADB, _ serial: String, _ code: Int) async -> Bool {
        await adb.shell(serial, "input keyevent \(code)").ok
    }

    /// Vertical swipe through the middle of the screen, away from the gesture-nav edges.
    private static func swipe(_ adb: ADB, _ serial: String, up: Bool) async -> Bool {
        let view = await adb.viewport(serial) ?? (landscape: false, width: 1080, height: 2400)
        let x = view.width / 2
        let low = view.height * 72 / 100
        let high = view.height * 28 / 100
        let (from, to) = up ? (low, high) : (high, low)
        return await adb.shell(serial, "input swipe \(x) \(from) \(x) \(to) 120").ok
    }

    /// exec-out merges the phone's stderr into the PNG stream (phones with a second
    /// screen print a warning), so stderr is dropped on the phone side.
    private static func screenshot(_ adb: ADB, _ serial: String) async -> Bool {
        let result = await Shell.run(adb.path, ["-s", serial, "exec-out", "screencap -p 2>/dev/null"],
                                     timeout: 15, includeStderr: false)
        let png = result.data
        guard result.ok, png.starts(with: [0x89, 0x50, 0x4E, 0x47]) else {
            Log.write("截图失败：\(result.output.prefix(200))")
            return false
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/手机截图 \(formatter.string(from: Date())).png")
        do {
            try png.write(to: url)
        } catch {
            Log.write("截图保存失败：\(error.localizedDescription)")
            return false
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(png, forType: .png)
        Log.write("截图已保存：\(url.path)")
        return true
    }
}
