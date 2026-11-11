// CodexGlow: a subtle screen-edge glow for completed turns and user-facing waits.
//
//   codex-glow show <done|decision|plan> [label] [event-id]
//   codex-glow hook                                  read Codex hook JSON on stdin

import AppKit
import Foundation

// MARK: - Paths

let glowHome = ProcessInfo.processInfo.environment["CODEX_GLOW_HOME"]
    ?? (NSHomeDirectory() as NSString).appendingPathComponent(".codex/glow")
let stateDir = (glowHome as NSString).appendingPathComponent("state")
let logFile = (glowHome as NSString).appendingPathComponent("glow.log")

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

/// A panel that can never take keyboard focus, so showing it never interrupts typing.
final class GlowPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

func safeComponent(_ value: String) -> String {
    let filtered = value.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    return String(filtered.prefix(100))
}

func pidPath(_ eventID: String) -> String {
    (stateDir as NSString).appendingPathComponent("display-\(safeComponent(eventID)).pid")
}

func killPrevious(_ eventID: String) {
    let path = pidPath(eventID)
    if let s = try? String(contentsOfFile: path, encoding: .utf8),
       let pid = pid_t(s.trimmingCharacters(in: .whitespacesAndNewlines)),
       pid != getpid() {
        kill(pid, SIGTERM)
    }
    try? String(getpid()).write(toFile: path, atomically: true, encoding: .utf8)
}

func show(_ kind: Kind, label: String, eventID: String) -> Never {
    ensureStateDir()
    killPrevious(eventID)

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let screens = NSScreen.screens
    guard !screens.isEmpty else {
        log("display_start_failed event_id=\(eventID) reason=no_screens")
        exit(2)
    }
    let windows: [(NSWindow, GlowView)] = screens.map { screen in
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
        return (window, view)
    }
    for (window, _) in windows { window.displayIfNeeded() }
    let visibleCount = windows.filter { $0.0.isVisible }.count
    guard visibleCount > 0 else {
        log("display_start_failed event_id=\(eventID) reason=no_window_visible")
        exit(2)
    }
    log("window_shown event_id=\(eventID) kind=\(kind.rawValue) screens=\(visibleCount)/\(screens.count)")

    Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in
        if let view = windows.first?.1, view.elapsed >= kind.duration {
            if (try? String(contentsOfFile: pidPath(eventID), encoding: .utf8)) == String(getpid()) {
                try? FileManager.default.removeItem(atPath: pidPath(eventID))
            }
            log("playback_finished event_id=\(eventID) kind=\(kind.rawValue)")
            exit(0)
        }
        for (_, view) in windows { view.needsDisplay = true }
    }
    app.run()
    exit(0)
}

// MARK: - hook

func stableHash(_ value: String) -> String {
    var hash: UInt64 = 14695981039346656037
    for byte in value.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 1099511628211
    }
    return String(hash, radix: 16)
}

func markerPath(_ prefix: String, session: String, turn: String = "", token: String = "") -> String {
    let key = [session, turn, token].map(stableHash).joined(separator: "-")
    return (stateDir as NSString).appendingPathComponent("\(prefix)-\(key)")
}

func markOnce(_ path: String) -> Bool {
    let fd = open(path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
    guard fd >= 0 else { return false }
    close(fd)
    return true
}

func claimMarker(_ path: String) -> (claimed: Bool, reason: String) {
    if markOnce(path) { return (true, "created") }
    if FileManager.default.fileExists(atPath: path) { return (false, "already_exists") }
    return (false, "marker_write_failed_errno_\(errno)")
}

func clearPending(session: String, turn: String? = nil, token: String? = nil) {
    let prefix = "pending-\(stableHash(session))-"
    let wanted = (stateDir as NSString).appendingPathComponent("pending-\(stableHash(session))-\(stableHash(turn ?? ""))-\(stableHash(token ?? ""))")
    if turn != nil, token != nil {
        try? FileManager.default.removeItem(atPath: wanted)
        return
    }
    guard let files = try? FileManager.default.contentsOfDirectory(atPath: stateDir) else { return }
    for file in files where file.hasPrefix(prefix) {
        let parts = file.split(separator: "-")
        if turn == nil || (parts.count > 2 && parts[2] == Substring(stableHash(turn!))) {
            try? FileManager.default.removeItem(atPath: (stateDir as NSString).appendingPathComponent(file))
        }
    }
}

func hasPending(session: String, turn: String) -> Bool {
    let prefix = "pending-\(stableHash(session))-\(stableHash(turn))-"
    guard let files = try? FileManager.default.contentsOfDirectory(atPath: stateDir) else { return false }
    return files.contains { $0.hasPrefix(prefix) }
}

func normalizedToolName(_ name: String) -> String {
    name.components(separatedBy: ".").last?.components(separatedBy: "__").last ?? name
}

func isQuestionTool(_ name: String) -> Bool {
    ["request_user_input", "request_user_input_async"].contains(normalizedToolName(name))
}

func hasCompleteProposedPlan(_ message: String) -> Bool {
    guard let open = message.range(of: "<proposed_plan>", options: [.caseInsensitive]),
          let close = message.range(of: "</proposed_plan>", options: [.caseInsensitive], range: open.upperBound..<message.endIndex) else {
        return false
    }
    let body = message[open.upperBound..<close.lowerBound]
        .trimmingCharacters(in: .whitespacesAndNewlines)
    // A reply that merely explains the marker may contain `<proposed_plan>…</proposed_plan>`.
    // Ellipsis-only placeholders are not submitted plans.
    return body.rangeOfCharacter(from: .alphanumerics) != nil
}

struct HookDecision {
    let kind: Kind?
    let reason: String
    let eventID: String
    let retryMarker: String?
}

// Some app builds omit plan text from Stop. Recover only this turn's final reply,
// never an earlier plan or a commentary message from the session.
func transcriptFinalMessage(_ j: [String: Any], session: String, turn: String) -> String? {
    guard let path = j["transcript_path"] as? String,
          let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    var matchesSession = false
    var currentTurn = ""
    var final: String?
    text.enumerateLines { line, _ in
        guard let data = line.data(using: .utf8),
              let row = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let payload = row["payload"] as? [String: Any] else { return }
        let type = row["type"] as? String ?? ""
        if type == "session_meta" {
            matchesSession = payload["id"] as? String == session
        } else if type == "turn_context" ||
                    (type == "event_msg" && payload["type"] as? String == "task_started") {
            currentTurn = payload["turn_id"] as? String ?? ""
        } else if matchesSession && currentTurn == turn && type == "response_item" &&
                    payload["type"] as? String == "message" && payload["role"] as? String == "assistant",
                  let phase = payload["phase"] as? String, ["final", "final_answer"].contains(phase),
                  let content = payload["content"] as? [[String: Any]] {
            final = content.filter { $0["type"] as? String == "output_text" }
                .compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
    }
    return final
}

func decide(_ j: [String: Any]) -> HookDecision {
    let event = j["hook_event_name"] as? String ?? "unknown"
    let session = j["session_id"] as? String ?? "unknown-session"
    let turn = j["turn_id"] as? String ?? "unknown-turn"
    let tool = j["tool_name"] as? String ?? ""
    let input = j["tool_input"]
    let callID = j["tool_use_id"] as? String
    let token = callID ?? "\(tool):\(stableHash(String(describing: input ?? "")))"

    switch event {
    case "UserPromptSubmit":
        clearPending(session: session)
        _ = markOnce(markerPath("started", session: session, turn: turn))
        return HookDecision(kind: nil, reason: "new_user_turn_reset_pending", eventID: "", retryMarker: nil)
    case "PreToolUse":
        guard isQuestionTool(tool) else {
            return HookDecision(kind: nil, reason: tool.isEmpty ? "tool_name_missing" : "unmatched_tool", eventID: "", retryMarker: nil)
        }
        let once = markerPath("asked", session: session, turn: turn, token: token)
        let claim = claimMarker(once)
        guard claim.claimed else {
            return HookDecision(kind: nil, reason: claim.reason == "already_exists" ? "duplicate_question_tool_call" : claim.reason, eventID: "", retryMarker: nil)
        }
        let pending = markerPath("pending", session: session, turn: turn, token: token)
        let pendingClaim = claimMarker(pending)
        let reason = pendingClaim.claimed ? "question_tool_requested" : "question_tool_requested_\(pendingClaim.reason)"
        return HookDecision(kind: .decision, reason: reason, eventID: stableHash(once), retryMarker: once)
    case "PostToolUse":
        if isQuestionTool(tool) {
            clearPending(session: session, turn: turn, token: token)
            return HookDecision(kind: nil, reason: "question_tool_returned_pending_cleared", eventID: "", retryMarker: nil)
        }
        return HookDecision(kind: nil, reason: "post_tool_use", eventID: "", retryMarker: nil)
    case "PermissionRequest":
        let once = markerPath("permission", session: session, turn: turn, token: token)
        let claim = claimMarker(once)
        guard claim.claimed else {
            return HookDecision(kind: nil, reason: claim.reason == "already_exists" ? "duplicate_permission_request" : claim.reason, eventID: "", retryMarker: nil)
        }
        return HookDecision(kind: .decision, reason: "permission_request", eventID: stableHash(once), retryMarker: once)
    case "Stop":
        guard session != "unknown-session", turn != "unknown-turn", !session.isEmpty, !turn.isEmpty else {
            return HookDecision(kind: nil, reason: "missing_turn_identity", eventID: "", retryMarker: nil)
        }
        let transcriptMessage = transcriptFinalMessage(j, session: session, turn: turn)
        guard FileManager.default.fileExists(atPath: markerPath("started", session: session, turn: turn)) || transcriptMessage != nil else {
            return HookDecision(kind: nil, reason: "no_user_turn", eventID: "", retryMarker: nil)
        }
        let hookMessage = (j["last_assistant_message"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let message = (hookMessage.isEmpty ? transcriptMessage ?? "" : hookMessage)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, message != "/" else {
            return HookDecision(kind: nil, reason: "empty_completion", eventID: "", retryMarker: nil)
        }
        let kind: Kind
        let reason: String
        if hasCompleteProposedPlan(message) {
            clearPending(session: session, turn: turn)
            kind = .plan
            reason = "complete_proposed_plan"
        } else if hasPending(session: session, turn: turn) {
            return HookDecision(kind: nil, reason: "awaiting_question_answer", eventID: "", retryMarker: nil)
        } else if message.hasSuffix("?") || message.hasSuffix("？") {
            kind = .decision
            reason = "final_question_fallback"
        } else {
            kind = .done
            reason = "ordinary_completion"
        }
        let once = markerPath("stop", session: session, turn: turn)
        let claim = claimMarker(once)
        guard claim.claimed else {
            return HookDecision(kind: nil, reason: claim.reason == "already_exists" ? "duplicate_stop" : claim.reason, eventID: "", retryMarker: nil)
        }
        return HookDecision(kind: kind, reason: reason, eventID: stableHash(once), retryMarker: once)
    default:
        return HookDecision(kind: nil, reason: "unsupported_event", eventID: "", retryMarker: nil)
    }
}

func spawnDetached(_ args: [String]) -> (pid: pid_t?, error: Int32?) {
    let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
    var attr: posix_spawnattr_t? = nil
    let attrInit = posix_spawnattr_init(&attr)
    guard attrInit == 0 else { return (nil, attrInit) }
    let flagResult = posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
    guard flagResult == 0 else {
        posix_spawnattr_destroy(&attr)
        return (nil, flagResult)
    }
    var fa: posix_spawn_file_actions_t? = nil
    let actionsInit = posix_spawn_file_actions_init(&fa)
    guard actionsInit == 0 else {
        posix_spawnattr_destroy(&attr)
        return (nil, actionsInit)
    }
    let redirectInput = posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0)
    let redirectOutput = posix_spawn_file_actions_addopen(&fa, 1, logFile, O_WRONLY | O_CREAT | O_APPEND, S_IRUSR | S_IWUSR)
    let redirectErrors = posix_spawn_file_actions_addopen(&fa, 2, logFile, O_WRONLY | O_CREAT | O_APPEND, S_IRUSR | S_IWUSR)
    let redirectResult = [redirectInput, redirectOutput, redirectErrors].first { $0 != 0 }
    if let error = redirectResult {
        posix_spawn_file_actions_destroy(&fa)
        posix_spawnattr_destroy(&attr)
        return (nil, error)
    }
    let argv = ([exe] + args).map { strdup($0) } + [nil]
    var pid: pid_t = 0
    let result = posix_spawn(&pid, exe, &fa, &attr, argv, environ)
    argv.forEach { free($0) }
    posix_spawn_file_actions_destroy(&fa)
    posix_spawnattr_destroy(&attr)
    return result == 0 ? (pid, nil) : (nil, result)
}

/// Log hook events and app-process lifecycle without copying prompt or tool-input text.
func log(_ line: String) {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    let data = "\(f.string(from: Date())) \(line)\n".data(using: .utf8)!
    let fd = open(logFile, O_WRONLY | O_CREAT | O_APPEND, S_IRUSR | S_IWUSR)
    guard fd >= 0 else { return }
    data.withUnsafeBytes { bytes in
        if let base = bytes.baseAddress { _ = write(fd, base, data.count) }
    }
    close(fd)
}

func hook() -> Never {
    ensureStateDir()
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        log("event_received invalid_json=true bytes=\(data.count)")
        FileHandle.standardOutput.write("{}\n".data(using: .utf8)!)
        exit(0)
    }
    let event = j["hook_event_name"] as? String ?? "?"
    let session = j["session_id"] as? String ?? "unknown-session"
    let turn = j["turn_id"] as? String ?? "unknown-turn"
    let tool = j["tool_name"] as? String ?? ""
    let callID = j["tool_use_id"] as? String ?? ""
    log("event_received session=\(stableHash(session)) turn=\(stableHash(turn)) event=\(event) tool=\(tool.isEmpty ? "-" : tool) tool_use_id=\(callID.isEmpty ? "-" : stableHash(callID))")
    let result = decide(j)
    log("classification session=\(stableHash(session)) turn=\(stableHash(turn)) event=\(event) kind=\(result.kind?.rawValue ?? "none") reason=\(result.reason)")
    guard let kind = result.kind else {
        FileHandle.standardOutput.write("{}\n".data(using: .utf8)!)
        exit(0)
    }
    let cwd = j["cwd"] as? String ?? ""
    let label = cwd.isEmpty ? "" : (cwd as NSString).lastPathComponent
    if ProcessInfo.processInfo.environment["CODEX_GLOW_DRY_RUN"] == "1" {
        log("animation_dry_run event_id=\(result.eventID) kind=\(kind.rawValue)")
    } else {
        let spawned = spawnDetached(["show", kind.rawValue, label, result.eventID])
        if let pid = spawned.pid {
            log("animation_spawn_succeeded event_id=\(result.eventID) kind=\(kind.rawValue) pid=\(pid)")
        } else {
            let code = spawned.error ?? EINVAL
            log("animation_spawn_failed event_id=\(result.eventID) kind=\(kind.rawValue) errno=\(code) error=\(String(cString: strerror(code)))")
            if let marker = result.retryMarker { try? FileManager.default.removeItem(atPath: marker) }
        }
    }
    FileHandle.standardOutput.write("{}\n".data(using: .utf8)!)
    exit(0)
}

// MARK: - main

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "show":
    let kind = Kind(rawValue: args.count > 2 ? args[2] : "") ?? .done
    show(kind, label: args.count > 3 ? args[3] : "", eventID: args.count > 4 ? args[4] : "manual")
case "hook":
    hook()
case "snapshot":
    // codex-glow snapshot <kind> <seconds> <out.png>: render one frame offscreen (for tuning)
    let kind = Kind(rawValue: args[2]) ?? .done
    let size = NSScreen.screens.first?.frame.size ?? NSSize(width: 1512, height: 982)
    let view = GlowView(frame: NSRect(origin: .zero, size: size), kind: kind, label: "Preview")
    view.fixedTime = Double(args[3]) ?? 0.5
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[4]))
    exit(0)
default:
    FileHandle.standardError.write("usage: codex-glow show <done|decision|plan> [label] [event-id] | codex-glow hook\n".data(using: .utf8)!)
    exit(2)
}
