//
//  @file        DiagnosticsTests.swift
//  @description DiagnosticsReport.render: every section is present, numbers keep fractional pointer rows
//               readable, missing values read as "none" / "not found", and display UUIDs never appear (I8).
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-11-26
//  @lastUpdated 2026-11-26
//
//  Run: xcodebuild test -project SpectaDockPin.xcodeproj -scheme SpectaDockPin -only-testing:SpectaDockPinTests/DiagnosticsTests
//

import CoreGraphics
import Foundation
import Testing
@testable import SpectaDockPin

/// Kennt's desk with the iPad (Sidecar) under the Dell (DESIGN §8 R7).
private func report() -> DiagnosticsReport {
    DiagnosticsReport(
        generated: Date(timeIntervalSince1970: 1_795_000_000),
        appVersion: "0.1.0 (1)",
        osVersion: "Version 27.0 (Build 26A1)",
        machine: "Mac16,10, arm64",
        status: #"pinned(anchorName: "LG HDR 4K")"#,
        pauseReason: "none",
        accessibilityTrusted: true,
        tapRunning: true,
        tapEnabled: true,
        anchorSetting: "main display",
        paused: false,
        launchAtLogin: true,
        dock: DockSettings(),
        dockWindow: CGRect(x: 0, y: 0, width: 3008, height: 1692),
        placement: "display(4)",
        userOverride: false,
        displays: [
            .init(id: 4, name: "LG HDR 4K", bounds: CGRect(x: 0, y: 0, width: 3008, height: 1692),
                  isMain: true, isBuiltin: false, isAnchor: true, mirrors: 0,
                  insets: .init(bottom: 49, left: 0, right: 0)),
            .init(id: 13, name: "Sidecar Display (AirPlay)", bounds: CGRect(x: 4465, y: 1440, width: 1103, height: 802),
                  isMain: false, isBuiltin: false, isAnchor: false, mirrors: 0, insets: nil),
        ],
        displayMapIsCurrent: true,
        guardActive: true,
        guardedRows: [CGRect(x: 3008, y: 1439, width: 1457, height: 1), CGRect(x: 4465, y: 2241, width: 1103, height: 1)],
        relocationPoint: CGPoint(x: 1504, y: 1691),
        droppedEvents: 351,
        blockedVisits: 4,
        tapDisabledByTimeout: 0,
        tapDisabledByUserInput: 1,
        lastOptionPassAgo: nil,
        phase: "idle",
        failedAttempts: 0,
        lastRelocation: nil,
        lastRelocationSucceeded: false,
        asleep: false,
        screenLocked: false,
        onConsole: true,
        secondsSinceInput: 0.04
    )
}

struct DiagnosticsTests {
    @Test func everySectionIsThere() {
        let text = DiagnosticsReport.render(report())
        for line in ["SpectaDockPin diagnostics", "App: 0.1.0 (1)", "Mac: Mac16,10, arm64",
                     #"Status: pinned(anchorName: "LG HDR 4K")"#, "Pause reason: none",
                     "Permission: accessibility yes, tap running yes, tap enabled yes",
                     "Settings: pin to main display, paused no, launch at login yes",
                     "Dock settings: orientation bottom, autohide no, separate Spaces yes, hot corner bottom-left no, bottom-right no",
                     "Dock window: (0,0 3008x1692), placement display(4), moved with Option no",
                     "  [4] LG HDR 4K  (0,0 3008x1692)  main, anchor  insets bottom 49 left 0 right 0",
                     "  [13] Sidecar Display (AirPlay)  (4465,1440 1103x802)    no NSScreen",
                     "Guard: active yes, dropped events 351, blocked visits 4, tap disabled by timeout 0, by user input 1",
                     "  (3008,1439 1457x1)", "  (4465,2241 1103x1)", "Relocation point: (1504,1691)",
                     "Last Option pass-through: none", "Relocation: phase idle, failed attempts 0, last none",
                     "Session: asleep no, screen locked no, on console yes, input 0 s ago"] {
            #expect(text.contains(line + "\n"), "missing: \(line)")
        }
    }

    @Test func missingValuesReadPlainly() {
        var value = report()
        value.dockWindow = nil
        value.guardedRows = []
        value.relocationPoint = nil
        value.displayMapIsCurrent = false
        value.lastOptionPassAgo = 2.6
        let text = DiagnosticsReport.render(value)
        #expect(text.contains("Dock window: not found, placement display(4)"))
        #expect(text.contains("Guarded rows:\n  none\n"))
        #expect(text.contains("Relocation point: none"))
        #expect(text.contains("— STALE: the active displays have changed since:"))
        #expect(text.contains("Last Option pass-through: 3 s ago"))
    }

    @Test(arguments: [(1439.0, "1439"), (1439.5, "1439.50"), (-1728.0, "-1728"), (1439.96, "1439.96")])
    func numbers(value: CGFloat, expected: String) {
        #expect(DiagnosticsReport.number(value) == expected)
    }

    @Test func noDisplayUUIDs() {
        let text = DiagnosticsReport.render(report())
        #expect(text.range(of: #"[0-9A-F]{8}-[0-9A-F]{4}-"#, options: .regularExpression) == nil)
    }
}
