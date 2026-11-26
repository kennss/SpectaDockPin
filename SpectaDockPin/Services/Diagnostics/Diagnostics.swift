//
//  @file        Diagnostics.swift
//  @description "Copy Diagnostics" (DESIGN §6): one plain-text report of everything pinning depends on, for a
//               user to paste into a bug report instead of being asked to run tests. AppModel gathers a
//               DiagnosticsReport; rendering it is pure and unit-tested. DiagnosticsProbe reads the few
//               system facts the rest of the app never needs (versions, Mac model, NSScreen insets).
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-11-26
//  @lastUpdated 2026-11-26
//
//  Notes:
//  - English and not localized: the developer reads it, and it must read the same on every Mac.
//  - Display names, coordinates, settings and states only (I8). Display UUIDs are left out: they identify
//    the hardware and add nothing the display ID doesn't. Nothing is sent anywhere; the user pastes it.
//  - Coordinates are CG global points (origin top-left of the main display, y down), as in the rest of the
//    app. Insets come from NSScreen (frame − visibleFrame) and are the only Cocoa-derived values.
//
//  Key declared values:
//  - Guarded rows are the GuardSnapshot the tap is using right now, not a recomputation, so a stale
//    snapshot shows up as a mismatch with the displays listed above it.
//

import AppKit
import CoreGraphics

struct DiagnosticsReport: Sendable, Equatable {
    struct Insets: Sendable, Equatable {
        /// frame − visibleFrame on each side, in points. The top (menu bar) is not reported.
        var bottom: CGFloat
        var left: CGFloat
        var right: CGFloat
    }

    struct Display: Sendable, Equatable {
        let id: CGDirectDisplayID
        let name: String
        /// CG global bounds in points.
        let bounds: CGRect
        let isMain: Bool
        let isBuiltin: Bool
        let isAnchor: Bool
        /// The display this one mirrors; 0 when it mirrors none (CGDisplayMirrorsDisplay).
        let mirrors: CGDirectDisplayID
        /// Nil when no NSScreen matched the display ID.
        let insets: Insets?
    }

    var generated: Date
    var appVersion: String
    var osVersion: String
    var machine: String

    var status: String
    var pauseReason: String
    var accessibilityTrusted: Bool
    var tapRunning: Bool
    var tapEnabled: Bool

    var anchorSetting: String
    var paused: Bool
    var launchAtLogin: Bool

    var dock: DockSettings
    /// CG global bounds of the Dock's window; nil when it was not found.
    var dockWindow: CGRect?
    var placement: String
    var userOverride: Bool

    var displays: [Display]
    /// False when the active displays now differ from the map the app is using.
    var displayMapIsCurrent: Bool

    var guardActive: Bool
    var guardedRows: [CGRect]
    var relocationPoint: CGPoint?
    var droppedEvents: Int
    var blockedVisits: Int
    var tapDisabledByTimeout: Int
    var tapDisabledByUserInput: Int
    /// Seconds since the last trigger-row event let through with Option; nil when there was none.
    var lastOptionPassAgo: TimeInterval?

    var phase: String
    var failedAttempts: Int
    var lastRelocation: Date?
    var lastRelocationSucceeded: Bool

    var asleep: Bool
    var screenLocked: Bool
    var onConsole: Bool
    var secondsSinceInput: TimeInterval

    /// The text put on the clipboard. Pure.
    static func render(_ report: DiagnosticsReport) -> String {
        var lines: [String] = []
        func add(_ line: String) { lines.append(line) }

        add("SpectaDockPin diagnostics")
        add("Generated: \(report.generated.formatted(.iso8601))")
        add("App: \(report.appVersion)")
        add("macOS: \(report.osVersion)")
        add("Mac: \(report.machine)")
        add("")
        add("Status: \(report.status)")
        add("Pause reason: \(report.pauseReason)")
        add("Permission: accessibility \(yes(report.accessibilityTrusted)), tap running \(yes(report.tapRunning)), tap enabled \(yes(report.tapEnabled))")
        add("Settings: pin to \(report.anchorSetting), paused \(yes(report.paused)), launch at login \(yes(report.launchAtLogin))")
        let dock = report.dock
        add("Dock settings: orientation \(dock.orientation.rawValue), autohide \(yes(dock.autohide)), separate Spaces \(yes(dock.separateSpaces)), hot corner bottom-left \(yes(dock.bottomLeftHotCorner)), bottom-right \(yes(dock.bottomRightHotCorner))")
        add("Dock window: \(report.dockWindow.map(rect) ?? "not found"), placement \(report.placement), moved with Option \(yes(report.userOverride))")
        add("")
        add("Displays (CG points, origin top-left of the main display)\(report.displayMapIsCurrent ? "" : " — STALE: the active displays have changed since"):")
        for display in report.displays {
            var tags: [String] = []
            if display.isMain { tags.append("main") }
            if display.isBuiltin { tags.append("built-in") }
            if display.isAnchor { tags.append("anchor") }
            if display.mirrors != 0 { tags.append("mirrors [\(display.mirrors)]") }
            let insets = display.insets.map { "insets bottom \(number($0.bottom)) left \(number($0.left)) right \(number($0.right))" }
                ?? "no NSScreen"
            add("  [\(display.id)] \(display.name)  \(rect(display.bounds))  \(tags.joined(separator: ", "))  \(insets)")
        }
        if report.displays.isEmpty { add("  none") }
        add("")
        add("Guard: active \(yes(report.guardActive)), dropped events \(report.droppedEvents), blocked visits \(report.blockedVisits), tap disabled by timeout \(report.tapDisabledByTimeout), by user input \(report.tapDisabledByUserInput)")
        add("Guarded rows:")
        for row in report.guardedRows { add("  \(rect(row))") }
        if report.guardedRows.isEmpty { add("  none") }
        add("Relocation point: \(report.relocationPoint.map(point) ?? "none")")
        add("Last Option pass-through: \(report.lastOptionPassAgo.map { "\(number($0.rounded())) s ago" } ?? "none")")
        add("")
        let last = report.lastRelocation.map {
            "\($0.formatted(.iso8601)) \(report.lastRelocationSucceeded ? "succeeded" : "failed")"
        } ?? "none"
        add("Relocation: phase \(report.phase), failed attempts \(report.failedAttempts), last \(last)")
        add("Session: asleep \(yes(report.asleep)), screen locked \(yes(report.screenLocked)), on console \(yes(report.onConsole)), input \(number((report.secondsSinceInput * 10).rounded() / 10)) s ago")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func yes(_ value: Bool) -> String { value ? "yes" : "no" }

    /// Whole numbers without decimals, others with two (real pointer positions are fractional, R1).
    static func number(_ value: CGFloat) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", Double(value))
    }

    static func rect(_ rect: CGRect) -> String {
        "(\(number(rect.minX)),\(number(rect.minY)) \(number(rect.width))x\(number(rect.height)))"
    }

    static func point(_ point: CGPoint) -> String {
        "(\(number(point.x)),\(number(point.y)))"
    }
}

/// System facts only the diagnostics report needs.
@MainActor
enum DiagnosticsProbe {
    static var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    static var osVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    /// hw.model plus the architecture this process runs as (x86_64 on Apple silicon means Rosetta).
    static var machine: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        let name = sysctlbyname("hw.model", &model, &size, nil, 0) == 0
            ? String(decoding: model.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            : "unknown"
        #if arch(arm64)
        return "\(name), arm64"
        #else
        return "\(name), x86_64"
        #endif
    }

    /// NSScreen insets by display ID.
    static func screenInsets() -> [CGDirectDisplayID: DiagnosticsReport.Insets] {
        var result: [CGDirectDisplayID: DiagnosticsReport.Insets] = [:]
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { continue }
            let frame = screen.frame, visible = screen.visibleFrame
            result[number.uint32Value] = DiagnosticsReport.Insets(bottom: visible.minY - frame.minY,
                                                                  left: visible.minX - frame.minX,
                                                                  right: frame.maxX - visible.maxX)
        }
        return result
    }
}
