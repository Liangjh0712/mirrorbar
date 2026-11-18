import AppKit
import ApplicationServices

/// Sends scrcpy's own shortcuts to its window. ⌘O turns the phone screen off
/// while mirroring and input keep working, without restarting scrcpy.
/// (`cmd display power-off` over adb also darkens the screen, but the phone then
/// drops touches.)
@MainActor
enum ScrcpyKeys {
    private static var prompted = false

    /// Posting key events needs the Accessibility permission. Asks for it once per launch.
    static func ready() -> Bool {
        if AXIsProcessTrusted() { return true }
        if !prompted {
            prompted = true
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            Log.write("没有辅助功能权限，息屏退回重启镜像的方式；到系统设置 › 隐私与安全性 › 辅助功能里打开 Mirrorbar")
        }
        return false
    }

    /// ⌘O: screen off. ⌘⇧O: screen on.
    static func screen(on: Bool, pid: pid_t) async -> Bool {
        guard ready() else { return false }
        // SDL only reads keys in its focused window. The toolbar never takes focus,
        // so this matters only for mirrorbar:// links sent from elsewhere.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
            NSRunningApplication(processIdentifier: pid)?.activate()
            try? await Task.sleep(for: .milliseconds(250))
        }
        // SDL takes modifiers from their own key events, not from a key's flags,
        // so ⌘ (and ⇧) go down and up around the O like a real press.
        let source = CGEventSource(stateID: .privateState)
        var flags: CGEventFlags = .maskCommand
        var sequence: [(CGKeyCode, Bool)] = [(55, true)]
        if on { flags.insert(.maskShift); sequence.append((56, true)) }
        sequence += [(31, true), (31, false)]
        if on { sequence.append((56, false)) }
        sequence.append((55, false))
        for (key, down) in sequence {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            else { return false }
            let releasing = !down && (key == 55 || key == 56)
            event.flags = releasing ? (key == 56 ? .maskCommand : []) : flags
            event.postToPid(pid)
            try? await Task.sleep(for: .milliseconds(20))
        }
        Log.write(on ? "手机亮屏（⌘⇧O）" : "手机息屏（⌘O）")
        return true
    }
}
