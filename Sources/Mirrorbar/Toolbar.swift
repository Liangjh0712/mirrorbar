import AppKit
import SwiftUI

/// Floating button strip glued to the right side of the scrcpy window.
@MainActor
final class ToolbarController {
    private let session: MirrorSession
    private var panel: NSPanel?
    private var timer: Timer?
    private var lastHover = Date()

    init(session: MirrorSession) {
        self.session = session
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard Prefs.current.showToolbar,
              let pid = session.scrcpyPID,
              let window = Self.windowFrame(pid: pid)
        else { hide(); return }

        // Only next to the mirror window when it is in front (or pinned on top).
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard Prefs.current.alwaysOnTop || front == pid || front == getpid() else { hide(); return }

        let panel = self.panel ?? makePanel()
        let size = panel.frame.size
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: window.midX, y: window.midY)) }
            ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? window
        var x = window.maxX + 10
        if x + size.width > bounds.maxX { x = window.minX - 10 - size.width }
        if x < bounds.minX { x = window.maxX - size.width - 10 }  // full screen: overlay inside
        var y = window.midY - size.height / 2
        y = min(max(y, bounds.minY + 8), bounds.maxY - size.height - 8)
        let origin = NSPoint(x: x.rounded(), y: y.rounded())
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }

        // Fade a little when the pointer has been away for a while.
        if panel.frame.insetBy(dx: -12, dy: -12).contains(NSEvent.mouseLocation) { lastHover = Date() }
        let alpha: CGFloat = Date().timeIntervalSince(lastHover) > 3 ? 0.85 : 1
        if panel.alphaValue != alpha {
            NSAnimationContext.runAnimationGroup { $0.duration = 0.25; panel.animator().alphaValue = alpha }
        }
        if !panel.isVisible {
            lastHover = Date()
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
    }

    private func hide() {
        if panel?.isVisible == true { panel?.orderOut(nil) }
    }

    private func makePanel() -> NSPanel {
        let view = ToolbarView { [weak self] action in
            await self?.session.perform(action) ?? false
        }
        let hosting = FirstMouseHostingView(rootView: view)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]

        // AppKit blur with state .active: SwiftUI materials go flat and see-through
        // in a window that is never key.
        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        // maskImage (not a layer corner radius) also clips the blur and the window shadow;
        // a layer mask left white square corners.
        blur.maskImage = Self.roundedMask(radius: Self.cornerRadius)
        blur.addSubview(hosting)

        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.contentView = blur
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.invalidateShadow()
        self.panel = panel
        return panel
    }

    static let cornerRadius: CGFloat = 22

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    /// Frame of the scrcpy window in Cocoa coordinates (origin bottom-left of the menu bar display).
    private static func windowFrame(pid: pid_t) -> NSRect? {
        guard let rect = Screens.cgFrame(pid: pid), let primary = NSScreen.screens.first else { return nil }
        return NSRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}

/// Lets the first click on a button work without activating Mirrorbar.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct ToolbarView: View {
    let perform: (PhoneAction) async -> Bool

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(PhoneAction.groups.enumerated()), id: \.offset) { index, group in
                if index > 0 {
                    Divider().frame(width: 22).padding(.vertical, 5)
                }
                ForEach(group) { action in
                    ToolButton(action: action, perform: perform)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 5)
        .overlay(RoundedRectangle(cornerRadius: ToolbarController.cornerRadius)
            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
    }
}

struct ToolButton: View {
    let action: PhoneAction
    let perform: (PhoneAction) async -> Bool

    @AppStorage(Key.turnScreenOff) private var screenOff = true
    @State private var hovering = false
    @State private var feedback: Bool?

    var body: some View {
        Button {
            Task {
                let ok = await perform(action)
                // Only actions without a visible effect on the phone get a tick.
                if action == .screenshot || !ok {
                    feedback = ok
                    try? await Task.sleep(for: .seconds(1.2))
                    feedback = nil
                }
            }
        } label: {
            Image(systemName: feedback == nil ? symbol : (feedback! ? "checkmark" : "exclamationmark.triangle"))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(feedback == false ? Color.orange : (feedback == true ? Color.green : Color.primary))
                .frame(width: 38, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(hovering ? 0.10 : 0)))
        .onHover { hovering = $0 }
        .help(action == .screen ? (screenOff ? "手机亮屏" : "手机息屏（镜像照常）") : action.help)
    }

    /// The screen button shows what a click will do.
    private var symbol: String {
        action == .screen ? (screenOff ? "sun.max" : "moon") : action.symbol
    }
}
