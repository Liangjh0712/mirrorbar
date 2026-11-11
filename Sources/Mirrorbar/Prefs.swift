import Foundation

enum AudioMode: String, CaseIterable, Identifiable {
    case mac, both, off
    var id: String { rawValue }
    var label: String {
        switch self {
        case .mac: "只在 Mac 播放"
        case .both: "Mac 和手机都响"
        case .off: "关闭"
        }
    }
}

enum VideoCodec: String, CaseIterable, Identifiable {
    case h264, h265
    var id: String { rawValue }
    var label: String {
        switch self {
        case .h264: "H.264（兼容性最好）"
        case .h265: "H.265（同码率更清楚）"
        }
    }
}

enum KeyboardMode: String, CaseIterable, Identifiable {
    case sdk, uhid
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sdk: "默认（sdk）"
        case .uhid: "模拟实体键盘（uhid）"
        }
    }
}

/// Keys shared by @AppStorage in the views and by `Prefs.current`.
enum Key {
    static let scrcpyPath = "scrcpyPath"
    static let adbPath = "adbPath"
    static let fps = "fps"
    static let bitrateUSB = "bitrateUSB"
    static let bitrateWifi = "bitrateWifi"
    static let videoCodec = "videoCodec"
    static let maxSize = "maxSize"
    static let preferUSB = "preferUSB"
    static let autoWifi = "autoWifi"
    static let lockRefreshRate = "lockRefreshRate"
    static let autoReconnect = "autoReconnect"
    static let alwaysOnTop = "alwaysOnTop"
    static let turnScreenOff = "turnScreenOff"
    static let stayAwake = "stayAwake"
    static let audioMode = "audioMode"
    static let keyboardMode = "keyboardMode"
    static let screenName = "screenName"
    static let extraArgs = "extraArgs"
    static let knownIPs = "knownIPs"
    static let pendingRestore = "pendingSettingsRestore"
    static let showToolbar = "showToolbar"
}

struct Prefs {
    var scrcpyPath: String
    var adbPath: String
    var fps: Int
    var bitrateUSB: Int
    var bitrateWifi: Int
    var videoCodec: VideoCodec
    var maxSize: Int
    var preferUSB: Bool
    var autoWifi: Bool
    var lockRefreshRate: Bool
    var autoReconnect: Bool
    var alwaysOnTop: Bool
    var turnScreenOff: Bool
    var stayAwake: Bool
    var audioMode: AudioMode
    var keyboardMode: KeyboardMode
    var screenName: String
    var extraArgs: String
    var showToolbar: Bool

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.scrcpyPath: "/opt/homebrew/bin/scrcpy",
            Key.adbPath: NSHomeDirectory() + "/Library/Android/sdk/platform-tools/adb",
            Key.fps: 90,
            Key.bitrateUSB: 24,
            Key.bitrateWifi: 12,
            Key.videoCodec: VideoCodec.h265.rawValue,
            Key.maxSize: 0,
            Key.preferUSB: true,
            Key.autoWifi: true,
            Key.lockRefreshRate: true,
            Key.autoReconnect: true,
            Key.alwaysOnTop: false,
            Key.turnScreenOff: true,
            Key.stayAwake: true,
            Key.audioMode: AudioMode.mac.rawValue,
            Key.keyboardMode: KeyboardMode.sdk.rawValue,
            Key.screenName: "",
            Key.extraArgs: "",
            Key.showToolbar: true,
        ])
    }

    static var current: Prefs {
        let d = UserDefaults.standard
        return Prefs(
            scrcpyPath: d.string(forKey: Key.scrcpyPath) ?? "",
            adbPath: d.string(forKey: Key.adbPath) ?? "",
            fps: d.integer(forKey: Key.fps),
            bitrateUSB: d.integer(forKey: Key.bitrateUSB),
            bitrateWifi: d.integer(forKey: Key.bitrateWifi),
            videoCodec: VideoCodec(rawValue: d.string(forKey: Key.videoCodec) ?? "") ?? .h265,
            maxSize: d.integer(forKey: Key.maxSize),
            preferUSB: d.bool(forKey: Key.preferUSB),
            autoWifi: d.bool(forKey: Key.autoWifi),
            lockRefreshRate: d.bool(forKey: Key.lockRefreshRate),
            autoReconnect: d.bool(forKey: Key.autoReconnect),
            alwaysOnTop: d.bool(forKey: Key.alwaysOnTop),
            turnScreenOff: d.bool(forKey: Key.turnScreenOff),
            stayAwake: d.bool(forKey: Key.stayAwake),
            audioMode: AudioMode(rawValue: d.string(forKey: Key.audioMode) ?? "") ?? .mac,
            keyboardMode: KeyboardMode(rawValue: d.string(forKey: Key.keyboardMode) ?? "") ?? .sdk,
            screenName: d.string(forKey: Key.screenName) ?? "",
            extraArgs: d.string(forKey: Key.extraArgs) ?? "",
            showToolbar: d.bool(forKey: Key.showToolbar)
        )
    }
}

/// Last Wi-Fi IP seen for each USB serial, so Wi-Fi can reconnect without mDNS.
enum KnownIPs {
    static var all: [String: String] {
        UserDefaults.standard.dictionary(forKey: Key.knownIPs) as? [String: String] ?? [:]
    }

    static func set(_ ip: String, for serial: String) {
        var map = all
        guard map[serial] != ip else { return }
        map[serial] = ip
        UserDefaults.standard.set(map, forKey: Key.knownIPs)
        Log.write("记住 \(serial) 的 Wi-Fi 地址 \(ip)")
    }
}
