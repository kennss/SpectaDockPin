//
//  @file        Commands.swift
//  @description DockProbe's commands. Read-only: `info`, `where`. Records real input: `watch` (listen only)
//               and `guard` (drops trigger-row events). Moves the real cursor and Dock: `trigger`, `push`, `home`.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//
//  Notes:
//  - `trigger` and `home` post events at the HID level (.cghidEventTap), which moves the real cursor; both
//    put the cursor back where it was when they finish (§3 method). They never post drag events except
//    `trigger --kind drag`, which ends with a leftMouseUp because synthetic drags can leave the Dock stuck
//    in its drag state (§3 F10).
//  - `home` is a stand-in for the app's Relocator (§5.4) without its waiting rules beyond a basic check
//    (pressed button, locked screen, not on console, recent input); it is for putting the Dock back after
//    an experiment, not a model of the final behaviour.
//
//  Key declared values (units):
//  - driveInterval 16 ms between posted events (§3 method).
//  - relocationTimeout 2.0 s (measured 0.33–1.00 s, §3 F1).
//  - idleBeforeHome 0.5 s of no input before `home` moves the cursor.
//  - approachHeight 40 pt / approachStep 3 pt per event: `home` comes down onto the row (§3 F16).
//  - pollInterval 25 ms between drains/Dock checks in `watch` and `guard`.
//  - permissionCheckInterval 0.5 s; guard stops its tap first when Accessibility goes away (I4).
//

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum ProbeTuning {
    static let driveInterval: useconds_t = 16_000
    static let relocationTimeout: TimeInterval = 2.0
    static let idleBeforeHome: TimeInterval = 0.5
    /// `home --style approach` starts this far above the anchor's last row and moves down this much per event.
    static let approachHeight: CGFloat = 40
    static let approachStep: CGFloat = 3
    /// `push` waits at most this long for the cursor read to show its start point.
    static let startSettleTimeout: TimeInterval = 0.2
    static let pollInterval: Duration = .milliseconds(25)
    static let permissionCheckInterval: TimeInterval = 0.5
    static let defaultSessionSeconds: Double = 180
    static let defaultRecordedRows = 3
}

@MainActor
enum Commands {
    // MARK: - info / where

    static func info(_ args: inout Arguments) throws -> Int32 {
        let anchor = try args.optionalUInt32("anchor")
        try args.rejectUnknown()
        let displays = DisplayList.active()
        let layout = EdgeLayout(displays: displays, anchorID: anchor, recordedRows: 1)

        print("Displays (CG global points, top-left origin):")
        for (index, display) in displays.enumerated() {
            let tags = [display.isMain ? "main" : nil, display.isBuiltin ? "built-in" : nil,
                        index == layout.anchorIndex ? "anchor" : nil].compactMap { $0 }.joined(separator: ", ")
            print("  [\(display.id)] \(display.name)  \(rect(display.bounds))  \(tags)  uuid \(display.uuid)")
        }

        print("NSScreen insets (frame − visibleFrame, points; top is the menu bar and is not used):")
        print("  screensHaveSeparateSpaces = \(NSScreen.screensHaveSeparateSpaces)")
        for screen in NSScreen.screens {
            let frame = screen.frame, visible = screen.visibleFrame
            print(String(format: "  %@  bottom %.0f  left %.0f  right %.0f  top %.0f", screen.localizedName,
                         visible.minY - frame.minY, visible.minX - frame.minX,
                         frame.maxX - visible.maxX, frame.maxY - visible.maxY))
        }

        let locator = DockLocator()
        if let dock = locator.current() {
            print("Dock window: pid \(dock.pid)  window \(dock.windowID)  layer \(dock.layer) (dock level \(DockLocator.dockLayer))  onscreen \(dock.isOnScreen)  \(rect(dock.bounds))")
            print("  placement: \(describe(DockLocator.placement(of: dock.bounds, in: displays), displays))")
            if let again = locator.current() {
                print("  single-window re-read: \(again == dock ? "same" : "differs") (full scans \(locator.fullScans))")
            }
        } else {
            print("Dock window: not found")
        }

        print("Trigger rows (non-anchor displays, free bottom stretches):")
        for strip in layout.strips { print("  \(displays[strip.displayIndex].name)  \(rect(strip.rect))") }
        if layout.strips.isEmpty { print("  none") }
        print("Relocation point: \(layout.relocationPoint.map { point($0) } ?? "none")")

        print("Permissions: AXIsProcessTrusted \(AXIsProcessTrusted())  postEvent \(CGPreflightPostEventAccess())  listenEvent \(CGPreflightListenEventAccess())  screenCapture \(CGPreflightScreenCaptureAccess())")
        let session = SessionState.read()
        print("Session: onConsole \(session.onConsole.map(String.init) ?? "missing")  CGSSessionScreenIsLocked \(session.screenLocked.map(String.init) ?? "missing")  keys \(session.keys.joined(separator: ", "))")
        print("Input: cursor \(point(CGEvent(source: nil)?.location ?? .zero))  buttons \(SessionState.pressedButtons())  idle \(String(format: "%.2f", SessionState.secondsSinceInput())) s")
        return 0
    }

    static func whereIs(_ args: inout Arguments) throws -> Int32 {
        try args.rejectUnknown()
        let displays = DisplayList.active()
        guard let dock = DockLocator().current() else {
            print("Dock window not found")
            return 1
        }
        print("Dock on \(describe(DockLocator.placement(of: dock.bounds, in: displays), displays))  window \(dock.windowID)  \(rect(dock.bounds))")
        return 0
    }

    // MARK: - watch / guard

    static func session(_ args: inout Arguments, mode: TapMode) async throws -> Int32 {
        let seconds = try args.double("secs", default: ProbeTuning.defaultSessionSeconds)
        let rows = try args.int("rows", default: ProbeTuning.defaultRecordedRows)
        let corner = CornerPolicy(rawValue: args.string("corner", default: CornerPolicy.block.rawValue))
        let optionBypass = !args.flag("no-option")
        let raw = args.flag("raw")
        let anchor = try args.optionalUInt32("anchor")
        try args.rejectUnknown()
        guard let corner else { throw UsageError(description: "--corner is block or pass") }

        let displays = DisplayList.active()
        guard displays.count > 1 else {
            print("Only one display is connected; there is nothing to guard or record.")
            return 1
        }
        let layout = EdgeLayout(displays: displays, anchorID: anchor, recordedRows: rows)
        let rule = EdgeRule(layout: layout, cornerPolicy: corner, optionBypass: optionBypass)
        let tap = EdgeTap(mode: mode, rule: rule)
        let origin = ProcessInfo.processInfo.systemUptime

        let modeText = mode == .guardDrop ? "GUARD (drops trigger-row events)" : "WATCH (listen only, changes nothing)"
        print("\(modeText) for \(Int(seconds)) s — Ctrl-C to stop")
        print("  anchor \(displays[layout.anchorIndex].name); corner \(corner.rawValue); option bypass \(optionBypass ? "on" : "off"); rows recorded \(layout.recordedRows)")
        for strip in layout.strips { print("  trigger row \(displays[strip.displayIndex].name) \(rect(strip.rect))") }

        guard tap.start() else {
            print(mode == .guardDrop
                  ? "Could not create the tap: this terminal needs the Accessibility permission."
                  : "Could not create the tap: this terminal needs the Input Monitoring permission.")
            return 2
        }
        let stopper = StopSignal()
        let recorder = EdgeRecorder(layout: layout, mode: mode, raw: raw, origin: origin)
        let locator = DockLocator()
        var nextPermissionCheck = origin
        var reenabled = 0
        var exitCode: Int32 = 0

        while !stopper.requested {
            let now = ProcessInfo.processInfo.systemUptime
            if now - origin >= seconds { break }
            if now >= nextPermissionCheck {
                nextPermissionCheck = now + ProbeTuning.permissionCheckInterval
                if mode == .guardDrop, !AXIsProcessTrusted() {
                    tap.stop()
                    print("Accessibility permission went away — tap removed first (I4).")
                    exitCode = 3
                    break
                }
                if tap.reenableIfDisabled() { reenabled += 1 }
            }
            let (events, _) = tap.drain()
            recorder.ingest(events)
            if let dock = locator.current() {
                recorder.observeDock(DockLocator.placement(of: dock.bounds, in: displays), at: now)
            } else {
                recorder.observeDock(.unknown, at: now)
            }
            try? await Task.sleep(for: ProbeTuning.pollInterval)
        }

        tap.stop()
        let (events, counters) = tap.drain()
        recorder.ingest(events)
        recorder.finish(at: ProcessInfo.processInfo.systemUptime, counters: counters)
        if reenabled > 0 { print("Safety net re-enabled the tap \(reenabled) time(s).") }
        if locator.fullScans > 1 { print("Dock window cache misses: \(locator.fullScans - 1)") }
        return exitCode
    }

    // MARK: - trigger

    static func trigger(_ args: inout Arguments) throws -> Int32 {
        guard args.positional.count == 2, let x = Double(args.positional[0]), let y = Double(args.positional[1]) else {
            throw UsageError(description: "trigger needs <x> <y> in CG global points")
        }
        let seconds = try args.double("secs", default: 4)
        let deltaY = Int64(try args.int("dy", default: 0))
        let post = args.string("post", default: "hid")
        let kind = args.string("kind", default: "moved")
        let withGuard = args.flag("guard")
        let corner = CornerPolicy(rawValue: args.string("corner", default: CornerPolicy.block.rawValue))
        try args.rejectUnknown()
        guard ["hid", "session", "pid"].contains(post) else { throw UsageError(description: "--post is hid, session or pid") }
        guard ["moved", "drag", "once"].contains(kind) else { throw UsageError(description: "--kind is moved, drag or once") }
        guard let corner else { throw UsageError(description: "--corner is block or pass") }

        let target = CGPoint(x: x, y: y)
        let displays = DisplayList.active()
        let locator = DockLocator()
        guard let before = locator.current() else {
            print("Dock window not found")
            return 1
        }
        guard let dockPID = DockLocator.dockPID() else { return 1 }

        var tap: EdgeTap?
        if withGuard {
            let layout = EdgeLayout(displays: displays, anchorID: nil, recordedRows: 1)
            let guardTap = EdgeTap(mode: .guardDrop, rule: EdgeRule(layout: layout, cornerPolicy: corner, optionBypass: true))
            guard guardTap.start() else {
                print("Could not create the guard tap (Accessibility permission?)")
                return 2
            }
            tap = guardTap
            usleep(200_000)
        }

        let saved = CGEvent(source: nil)?.location ?? .zero
        print("Dock on \(describe(DockLocator.placement(of: before.bounds, in: displays), displays)); cursor \(point(saved))")
        print("Posting \(kind) at \(point(target)) dy \(deltaY) via \(post) for up to \(seconds) s\(withGuard ? " with guard" : "")")

        let start = ProcessInfo.processInfo.systemUptime
        var movedAfter: TimeInterval?
        var posted = 0
        while ProcessInfo.processInfo.systemUptime - start < seconds {
            if kind != "once" || posted == 0 {
                let type: CGEventType = kind == "drag" ? .leftMouseDragged : .mouseMoved
                if let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: target, mouseButton: .left) {
                    event.setIntegerValueField(.mouseEventDeltaY, value: deltaY)
                    event.setIntegerValueField(.eventSourceUserData, value: ProbeMarker.value)
                    switch post {
                    case "session": event.post(tap: .cgSessionEventTap)
                    case "pid": event.postToPid(dockPID)
                    default: event.post(tap: .cghidEventTap)
                    }
                    posted += 1
                }
            }
            usleep(ProbeTuning.driveInterval)
            if let now = locator.current(), now.bounds != before.bounds {
                movedAfter = ProcessInfo.processInfo.systemUptime - start
                break
            }
        }
        let cursorDuring = CGEvent(source: nil)?.location ?? .zero
        if kind == "drag", let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: cursorDuring, mouseButton: .left) {
            up.setIntegerValueField(.eventSourceUserData, value: ProbeMarker.value)
            up.post(tap: .cghidEventTap)
        }
        CGWarpMouseCursorPosition(saved)

        if let tap {
            tap.stop()
            let (_, counters) = tap.drain()
            print("Guard: seen \(counters.seen), dropped \(counters.dropped)")
        }
        let after = locator.current().map { describe(DockLocator.placement(of: $0.bounds, in: displays), displays) } ?? "unknown"
        if let movedAfter {
            print(String(format: "MOVED after %.2f s (%d events) → Dock on %@", movedAfter, posted, after))
        } else {
            print("No move in \(seconds) s (\(posted) events); Dock on \(after)")
        }
        print("Cursor during \(point(cursorDuring)); restored to \(point(CGEvent(source: nil)?.location ?? .zero))")
        return 0
    }

    // MARK: - push

    /// Emulates a real mouse pushed against a bottom edge: every step starts from wherever the cursor is
    /// now (so another process warping the cursor is respected, unlike `trigger`), moves by (dx, step) and
    /// is clamped to the display's last row, as the HID system clamps a real pointer.
    static func push(_ args: inout Arguments) throws -> Int32 {
        guard args.positional.count == 2, let x = Double(args.positional[0]), let y = Double(args.positional[1]) else {
            throw UsageError(description: "push needs a start <x> <y> in CG global points")
        }
        let seconds = try args.double("secs", default: 4)
        let step = try args.double("step", default: 3)
        let dx = try args.double("dx", default: 0)
        let trace = try args.int("trace", default: 0)
        try args.rejectUnknown()

        let displays = DisplayList.active()
        let start = CGPoint(x: x, y: y)
        guard let display = displays.first(where: { $0.bounds.contains(start) }) else {
            throw UsageError(description: "start point is not on any display")
        }
        let locator = DockLocator()
        guard let before = locator.current() else {
            print("Dock window not found")
            return 1
        }
        let saved = CGEvent(source: nil)?.location ?? .zero
        defer { CGWarpMouseCursorPosition(saved) }
        print("Dock on \(describe(DockLocator.placement(of: before.bounds, in: displays), displays)); pushing from \(point(start)) by (\(dx), \(step)) per 16 ms on \(display.name) for up to \(seconds) s")

        func post(_ location: CGPoint, deltaX: Double, deltaY: Double) {
            guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: location, mouseButton: .left) else { return }
            event.setIntegerValueField(.mouseEventDeltaX, value: Int64(deltaX.rounded()))
            event.setIntegerValueField(.mouseEventDeltaY, value: Int64(deltaY.rounded()))
            event.setIntegerValueField(.eventSourceUserData, value: ProbeMarker.value)
            event.post(tap: .cghidEventTap)
        }

        // A posted event is applied asynchronously, so reading the cursor right after posting can still return
        // the old position (seen 2026-10-18). Warp to the start, post it, and wait until the read agrees.
        CGWarpMouseCursorPosition(start)
        post(start, deltaX: 0, deltaY: 0)
        let settleStart = ProcessInfo.processInfo.systemUptime
        while let now = CGEvent(source: nil)?.location, abs(now.x - start.x) >= 0.5 || abs(now.y - start.y) >= 0.5 {
            guard ProcessInfo.processInfo.systemUptime - settleStart < ProbeTuning.startSettleTimeout else {
                print("Cursor did not reach the start point (read \(point(now)))")
                return 1
            }
            usleep(2_000)
        }
        let began = ProcessInfo.processInfo.systemUptime
        var posted = 0, onLastRow = 0, warpedAway = 0
        var lastPosted = start
        var previousPosted = start
        var movedAfter: TimeInterval?
        while ProcessInfo.processInfo.systemUptime - began < seconds {
            let current = CGEvent(source: nil)?.location ?? lastPosted
            // The read can lag one posted event behind (≈16 ms), so only a position that matches neither of the
            // last two posted points counts as someone else moving the cursor.
            func differs(_ a: CGPoint, _ b: CGPoint) -> Bool { abs(a.x - b.x) >= 1 || abs(a.y - b.y) >= 1 }
            if differs(current, lastPosted), differs(current, previousPosted) { warpedAway += 1 }
            let next = CGPoint(
                x: min(max(current.x + dx, display.bounds.minX), display.bounds.maxX - 1),
                y: min(current.y + step, display.bounds.maxY - 1)
            )
            post(next, deltaX: dx, deltaY: step)
            posted += 1
            if posted <= trace { print("  step \(posted): cursor read \(point(current)) → posted \(point(next))") }
            if next.y >= display.bounds.maxY - 1 { onLastRow += 1 }
            previousPosted = lastPosted
            lastPosted = next
            usleep(ProbeTuning.driveInterval)
            if let now = locator.current(), now.bounds != before.bounds {
                movedAfter = ProcessInfo.processInfo.systemUptime - began
                break
            }
        }
        let after = locator.current().map { describe(DockLocator.placement(of: $0.bounds, in: displays), displays) } ?? "unknown"
        let result = movedAfter.map { String(format: "MOVED after %.2f s", $0) } ?? "No move in \(seconds) s"
        print("\(result); \(posted) events, \(onLastRow) on the last row, cursor found moved by someone else \(warpedAway) times; Dock on \(after)")
        return 0
    }

    // MARK: - home

    static func home(_ args: inout Arguments) throws -> Int32 {
        let anchor = try args.optionalUInt32("anchor")
        let style = args.string("style", default: "approach")
        try args.rejectUnknown()
        guard ["approach", "point"].contains(style) else { throw UsageError(description: "--style is approach or point") }
        let displays = DisplayList.active()
        let layout = EdgeLayout(displays: displays, anchorID: anchor, recordedRows: 1)
        let locator = DockLocator()
        guard let before = locator.current() else {
            print("Dock window not found")
            return 1
        }
        if DockLocator.placement(of: before.bounds, in: displays) == .display(index: layout.anchorIndex) {
            print("Dock is already on \(displays[layout.anchorIndex].name) (window \(before.windowID) \(rect(before.bounds)))")
            return 0
        }
        guard let target = layout.relocationPoint else {
            print("The anchor display has no free bottom edge")
            return 1
        }
        let session = SessionState.read()
        if session.screenLocked == true || session.onConsole == false {
            print("Not moving the cursor: screen locked or session not on console")
            return 1
        }
        if SessionState.pressedButtons() != "none" {
            print("Not moving the cursor: a mouse button is down (§3 F10)")
            return 1
        }
        let idle = SessionState.secondsSinceInput()
        if idle < ProbeTuning.idleBeforeHome {
            usleep(useconds_t((ProbeTuning.idleBeforeHome - idle) * 1_000_000))
        }

        let saved = CGEvent(source: nil)?.location ?? .zero
        defer { CGWarpMouseCursorPosition(saved) }
        // "approach" comes down onto the row from above like a real pointer; "point" posts on the row only.
        // After the pointer pushed on the bottom of the Dock's own display, "point" can fail for minutes while
        // "approach" still works (§3 F16).
        var position = style == "approach"
            ? CGPoint(x: target.x, y: target.y - ProbeTuning.approachHeight)
            : target
        let start = ProcessInfo.processInfo.systemUptime
        while ProcessInfo.processInfo.systemUptime - start < ProbeTuning.relocationTimeout {
            if let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: position, mouseButton: .left) {
                event.setIntegerValueField(.mouseEventDeltaY, value: position.y < target.y ? Int64(ProbeTuning.approachStep) : 0)
                event.setIntegerValueField(.eventSourceUserData, value: ProbeMarker.value)
                event.post(tap: .cghidEventTap)
            }
            position.y = min(position.y + ProbeTuning.approachStep, target.y)
            usleep(ProbeTuning.driveInterval)
            if let now = locator.current(),
               DockLocator.placement(of: now.bounds, in: displays) == .display(index: layout.anchorIndex) {
                print(String(format: "Dock back on %@ after %.2f s", displays[layout.anchorIndex].name,
                             ProcessInfo.processInfo.systemUptime - start))
                return 0
            }
        }
        print("Dock did not move back within \(ProbeTuning.relocationTimeout) s")
        return 1
    }

    // MARK: - formatting

    static func rect(_ r: CGRect) -> String {
        String(format: "{%.1f, %.1f, %.1f × %.1f}", r.minX, r.minY, r.width, r.height)
    }

    static func point(_ p: CGPoint) -> String {
        String(format: "(%.1f, %.1f)", p.x, p.y)
    }

    static func describe(_ placement: DockPlacement, _ displays: [DisplayInfo]) -> String {
        switch placement {
        case .display(let index): "\(displays[index].name) [\(displays[index].id)]"
        case .unknown: "unknown"
        }
    }
}

/// Session and input state the probe checks before moving the cursor.
enum SessionState {
    struct Snapshot {
        let onConsole: Bool?
        let screenLocked: Bool?
        let keys: [String]
    }

    static func read() -> Snapshot {
        let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
        return Snapshot(
            onConsole: (dictionary[kCGSessionOnConsoleKey as String] as? NSNumber)?.boolValue,
            screenLocked: (dictionary["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue,
            keys: dictionary.keys.sorted()
        )
    }

    static func pressedButtons() -> String {
        let buttons: [(String, CGMouseButton)] = [("left", .left), ("right", .right), ("center", .center)]
        let down = buttons.filter { CGEventSource.buttonState(.hidSystemState, button: $0.1) }.map(\.0)
        return down.isEmpty ? "none" : down.joined(separator: "+")
    }

    /// Seconds since the last HID input of any kind (kCGAnyInputEventType).
    static func secondsSinceInput() -> TimeInterval {
        guard let any = CGEventType(rawValue: ~UInt32(0)) else { return .infinity }
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: any)
    }
}

/// Turns SIGINT/SIGTERM into a flag the session loop checks, so the tap is always removed before exit.
@MainActor
final class StopSignal {
    private(set) var requested = false
    private var sources: [DispatchSourceSignal] = []

    init() {
        for number in [SIGINT, SIGTERM] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.requested = true }
            }
            source.resume()
            sources.append(source)
        }
    }
}
