// ClaudeGlow: a subtle screen-edge glow that tells you what Claude Code is waiting on.
//
//   claude-glow show <done|decision|plan> [label]   play the effect, then exit
//   claude-glow hook                                read hook JSON on stdin, pick an effect,
//                                                   spawn `show` detached, exit at once

import AppKit
import Foundation

// MARK: - Paths

let glowHome = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/glow")
let stateDir = (glowHome as NSString).appendingPathComponent("state")
let pidFile = (stateDir as NSString).appendingPathComponent("current.pid")

func ensureStateDir() {
    try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
}

// MARK: - Effect kinds

enum Kind: String {
    case done, decision, plan

    var color: NSColor {
        switch self {
        case .done: return NSColor(srgbRed: 0.05, green: 0.72, blue: 0.30, alpha: 1)
        case .decision: return NSColor(srgbRed: 1.00, green: 0.55, blue: 0.00, alpha: 1)
        case .plan: return NSColor(srgbRed: 0.35, green: 0.28, blue: 1.00, alpha: 1)
        }
    }

    var title: String {
        switch self {
        case .done: return "✓ 完成"
        case .decision: return "? 等你决定"
        case .plan: return "✦ 方案就绪"
        }
    }

    var duration: Double {
        switch self {
        case .done: return 2.0
        case .decision: return 2.8
        case .plan: return 2.6
        }
    }
}

func smooth(_ x: Double) -> Double {
    let t = min(max(x, 0), 1)
    return t * t * (3 - 2 * t)
}

/// Edge glow strength (0...1) at time t.
func edgeIntensity(_ kind: Kind, _ t: Double) -> Double {
    switch kind {
    case .done:
        // fade in, hold, fade out
        if t < 0.25 { return smooth(t / 0.25) }
        if t < 0.85 { return 1 }
        return 1 - smooth((t - 0.85) / (kind.duration - 0.85))
    case .decision:
        // two breaths
        let s = sin(Double.pi * t / 1.4)
        return s * s
    case .plan:
        // edges come up after the top sweep
        if t < 0.9 { return 0 }
        if t < 1.2 { return smooth((t - 0.9) / 0.3) * 0.8 }
        return 0.8 * (1 - smooth((t - 1.2) / (kind.duration - 1.2)))
    }
}

/// Position (0...1) and strength of the plan's light band along the top edge, or nil.
func sweep(_ kind: Kind, _ t: Double) -> (x: Double, a: Double)? {
    guard kind == .plan, t < 1.3 else { return nil }
    let x = smooth(t / 1.1)
    let a = t < 0.15 ? t / 0.15 : (t > 1.1 ? 1 - (t - 1.1) / 0.2 : 1)
    return (x, max(a, 0))
}

func labelAlpha(_ kind: Kind, _ t: Double) -> Double {
    let d = kind.duration
    if t < 0.15 { return 0 }
    if t < 0.4 { return smooth((t - 0.15) / 0.25) }
    if t > d - 0.5 { return 1 - smooth((t - (d - 0.5)) / 0.5) }
    return 1
}

// MARK: - View

final class GlowView: NSView {
    let kind: Kind
    let label: String
    let start = Date()
    let thickness: CGFloat = 70
    let peakAlpha: CGFloat = 0.9

    init(frame: NSRect, kind: Kind, label: String) {
        self.kind = kind
        self.label = label
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    var fixedTime: Double? = nil  // for `snapshot`
    var elapsed: Double { fixedTime ?? Date().timeIntervalSince(start) }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let t = elapsed
        let b = bounds
        let base = kind.color

        let i = CGFloat(edgeIntensity(kind, t))
        if i > 0.001 {
            drawEdges(ctx, b, base.withAlphaComponent(peakAlpha * i))
        }

        if let s = sweep(kind, t), s.a > 0 {
            let cx = b.minX + CGFloat(s.x) * b.width
            let band = NSGradient(colors: [
                base.withAlphaComponent(0.9 * CGFloat(s.a)),
                base.withAlphaComponent(0),
            ])!
            // a flattened radial glow hugging the top edge
            ctx.saveGState()
            ctx.translateBy(x: cx, y: b.maxY)
            ctx.scaleBy(x: 1, y: 0.3)
            band.draw(fromCenter: .zero, radius: 0, toCenter: .zero, radius: 280, options: [])
            ctx.restoreGState()
        }

        let la = CGFloat(labelAlpha(kind, t))
        if la > 0.001 { drawLabel(b, alpha: la) }
    }

    /// One inner glow for the whole frame: a ring just outside the screen casts a blurred
    /// shadow inward, so the corners round off instead of stacking two gradients.
    private func drawEdges(_ ctx: CGContext, _ b: NSRect, _ c: NSColor) {
        let ring = CGMutablePath()
        ring.addRect(b.insetBy(dx: -thickness * 3, dy: -thickness * 3))
        ring.addRect(b)
        // a wide soft layer plus a tighter one, so the glow stays visible on white pages
        for blur in [thickness, thickness / 3] {
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: blur, color: c.cgColor)
            ctx.setFillColor(c.withAlphaComponent(1).cgColor)
            ctx.addPath(ring)
            ctx.fillPath(using: .evenOdd)
            ctx.restoreGState()
        }
    }

    private func drawLabel(_ b: NSRect, alpha: CGFloat) {
        let text = label.isEmpty ? kind.title : "\(kind.title) · \(label)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let pad = NSSize(width: 18, height: 8)
        let w = size.width + pad.width * 2, h = size.height + pad.height * 2
        let topInset: CGFloat = 44  // clear the menu bar / notch
        let rect = NSRect(x: b.midX - w / 2, y: b.maxY - topInset - h, width: w, height: h)
        let path = NSBezierPath(roundedRect: rect, xRadius: h / 2, yRadius: h / 2)
        NSColor(white: 0.08, alpha: 0.72 * alpha).setFill()
        path.fill()
        kind.color.withAlphaComponent(0.9 * alpha).setStroke()
        path.lineWidth = 1.5
        path.stroke()
        str.draw(at: NSPoint(x: rect.minX + pad.width, y: rect.minY + pad.height))
    }
}

// MARK: - show

func killPrevious() {
    if let s = try? String(contentsOfFile: pidFile, encoding: .utf8),
       let pid = pid_t(s.trimmingCharacters(in: .whitespacesAndNewlines)),
       pid != getpid() {
        kill(pid, SIGTERM)
    }
    try? String(getpid()).write(toFile: pidFile, atomically: true, encoding: .utf8)
}

/// A panel that can never take keyboard focus, so showing it never interrupts typing.
final class GlowPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

func show(_ kind: Kind, label: String) -> Never {
    ensureStateDir()
    killPrevious()

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    guard let screen = NSScreen.screens.first else { exit(0) }
    let window = GlowPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.ignoresMouseEvents = true
    window.level = .screenSaver
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    let view = GlowView(frame: NSRect(origin: .zero, size: screen.frame.size), kind: kind, label: label)
    window.contentView = view
    window.setFrame(screen.frame, display: false)
    window.orderFrontRegardless()

    Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in
        if view.elapsed >= kind.duration {
            if (try? String(contentsOfFile: pidFile, encoding: .utf8)) == String(getpid()) {
                try? FileManager.default.removeItem(atPath: pidFile)
            }
            exit(0)
        }
        view.needsDisplay = true
    }
    app.run()
    exit(0)
}

// MARK: - hook

func markerPath(_ prefix: String, _ session: String) -> String {
    let safe = session.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    return (stateDir as NSString).appendingPathComponent("\(prefix)-\(safe.isEmpty ? "unknown" : safe)")
}

/// How long after a plan glow the approval prompt's own Notification is ignored.
let planQuietWindow: TimeInterval = 120

/// Decide which effect (if any) a hook payload should produce.
func decide(_ j: [String: Any]) -> Kind? {
    let event = j["hook_event_name"] as? String ?? ""
    let session = j["session_id"] as? String ?? ""

    switch event {
    case "PreToolUse":
        let tool = j["tool_name"] as? String ?? ""
        let input = j["tool_input"] as? [String: Any] ?? [:]
        switch tool {
        case "AskUserQuestion": return .decision
        case "ExitPlanMode":
            // The app follows this with a Notification for the approval prompt; remember the
            // plan so that one doesn't glow a second time.
            ensureStateDir()
            try? String(Date().timeIntervalSince1970).write(toFile: markerPath("plan", session), atomically: true, encoding: .utf8)
            return .plan
        case let t where t.hasSuffix("__wrap_up"):
            // The app's end-of-turn box: an `ask` means the turn ends on a question for you.
            let ask = (input["ask"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !ask.isEmpty {
                ensureStateDir()
                FileManager.default.createFile(atPath: markerPath("decision", session), contents: Data())
            }
            return nil
        default: return nil
        }
    case "Notification":
        // idle_prompt repeats a Stop we already showed; everything else (permission prompts,
        // dialogs) is waiting on you.
        if (j["notification_type"] as? String) == "idle_prompt" { return nil }
        let plan = markerPath("plan", session)
        if let s = try? String(contentsOfFile: plan, encoding: .utf8), let t = Double(s) {
            try? FileManager.default.removeItem(atPath: plan)
            if Date().timeIntervalSince1970 - t < planQuietWindow { return nil }
        }
        return .decision
    case "Stop":
        try? FileManager.default.removeItem(atPath: markerPath("plan", session))
        let marker = markerPath("decision", session)
        if FileManager.default.fileExists(atPath: marker) {
            try? FileManager.default.removeItem(atPath: marker)
            return .decision
        }
        let last = (j["last_assistant_message"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if last.hasSuffix("?") || last.hasSuffix("？") { return .decision }
        return .done
    default:
        return nil
    }
}

func spawnDetached(_ args: [String]) {
    let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
    var attr: posix_spawnattr_t? = nil
    posix_spawnattr_init(&attr)
    posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
    var fa: posix_spawn_file_actions_t? = nil
    posix_spawn_file_actions_init(&fa)
    for fd in [0, 1, 2] { posix_spawn_file_actions_addopen(&fa, Int32(fd), "/dev/null", O_RDWR, 0) }
    let argv = ([exe] + args).map { strdup($0) } + [nil]
    var pid: pid_t = 0
    posix_spawn(&pid, exe, &fa, &attr, argv, environ)
    argv.forEach { free($0) }
    posix_spawn_file_actions_destroy(&fa)
    posix_spawnattr_destroy(&attr)
}

/// You are already looking at Claude, so there is nothing to point you to.
func claudeIsFrontmost() -> Bool {
    if ProcessInfo.processInfo.environment["CLAUDE_GLOW_ALWAYS"] == "1" { return false }
    return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.anthropic.claudefordesktop"
}

let logFile = (glowHome as NSString).appendingPathComponent("glow.log")

/// One line per hook call, so a missing glow can be traced. Kept to the last 300 lines.
func log(_ line: String) {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let old = (try? String(contentsOfFile: logFile, encoding: .utf8)) ?? ""
    let lines = old.split(separator: "\n", omittingEmptySubsequences: true).suffix(299).map(String.init)
    try? (lines + ["\(f.string(from: Date())) \(line)"]).joined(separator: "\n").appending("\n")
        .write(toFile: logFile, atomically: true, encoding: .utf8)
}

func hook() -> Never {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        log("bad input")
        exit(0)
    }
    let event = j["hook_event_name"] as? String ?? "?"
    let detail = (j["tool_name"] as? String) ?? (j["notification_type"] as? String) ?? ""
    let session = String((j["session_id"] as? String ?? "").prefix(8))
    let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
    // decide() runs first so the decision marker is still written/consumed when we stay quiet
    guard let kind = decide(j) else {
        log("\(session) \(event) \(detail) -> none (front: \(front))")
        exit(0)
    }
    if claudeIsFrontmost() {
        log("\(session) \(event) \(detail) -> \(kind.rawValue) skipped, Claude in front")
        exit(0)
    }
    let cwd = j["cwd"] as? String ?? ""
    let label = cwd.isEmpty ? "" : (cwd as NSString).lastPathComponent
    spawnDetached(["show", kind.rawValue, label])
    log("\(session) \(event) \(detail) -> \(kind.rawValue) shown (front: \(front))")
    exit(0)
}

// MARK: - main

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "show":
    let kind = Kind(rawValue: args.count > 2 ? args[2] : "") ?? .done
    show(kind, label: args.count > 3 ? args[3] : "")
case "hook":
    hook()
case "snapshot":
    // claude-glow snapshot <kind> <seconds> <out.png>: render one frame offscreen (for tuning)
    let kind = Kind(rawValue: args[2]) ?? .done
    let size = NSScreen.screens.first?.frame.size ?? NSSize(width: 1512, height: 982)
    let view = GlowView(frame: NSRect(origin: .zero, size: size), kind: kind, label: "Preview")
    view.fixedTime = Double(args[3]) ?? 0.5
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[4]))
    exit(0)
default:
    FileHandle.standardError.write("usage: claude-glow show <done|decision|plan> [label] | claude-glow hook\n".data(using: .utf8)!)
    exit(2)
}
