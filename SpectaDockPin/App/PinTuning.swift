//
//  @file        PinTuning.swift
//  @description Every tuned number in SpectaDockPin, with its unit and where it was measured
//               (Docs/DESIGN.md §3). No magic numbers elsewhere.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//

import CoreGraphics
import Foundation

enum PinTuning {
    // MARK: Guard

    /// Height of the trigger row in points: only the last 1-pt row moves the Dock (F1, F2, F20, F21).
    static let triggerRowHeight: CGFloat = 1
    /// Safety net: how often the main side checks that the tap is still enabled (§5.2).
    static let tapCheckInterval: TimeInterval = 2
    /// After an Option-held pass-through, a Dock move within this window counts as the user's own (§5.2).
    static let optionOverrideWindow: TimeInterval = 3

    // MARK: Dock

    /// How often the Dock's position and preferences are re-read without an event (§5.3).
    static let pollInterval: TimeInterval = 3
    /// While the Dock moves it owns a second window for 0.10–0.25 s (F15); a scan waits this long for one.
    static let dockSettleTimeout: TimeInterval = 1
    /// Pause between scans while two Dock windows exist (F15).
    static let dockSettleInterval: Duration = .milliseconds(20)
    /// Tolerance when matching the Dock window to a display's bounds (F8).
    static let placementTolerance: CGFloat = 1

    // MARK: Displays

    /// Display changes arrive in bursts; wait this long after the last one before rebuilding (§5.1).
    static let displayDebounce: Duration = .milliseconds(500)
    /// Edges closer than this are treated as touching when finding displays directly below another.
    static let adjacencyTolerance: CGFloat = 0.5

    // MARK: Relocation (§5.4)

    /// Time between posted pointer events (§3 method).
    static let driveInterval: Duration = .milliseconds(16)
    /// The approach starts this far above the anchor's last row (F16).
    static let approachHeight: CGFloat = 40
    /// Points moved down per posted event during the approach (F16).
    static let approachStep: CGFloat = 3
    /// Give up a drive after this long on the row: measured 0.33–1.00 s (F1), 0.66–0.73 s with approach (F16).
    static let relocationTimeout: TimeInterval = 2.0
    /// The pointer must have been still this long before the app moves it (I3).
    static let idleBeforeRelocation: TimeInterval = 0.5
    /// When a relocation has to wait (I3), check again after this long.
    static let waitRecheckInterval: Duration = .milliseconds(500)
    /// Delays before the second, third and fourth attempt after a failed drive (§5.4 step 5).
    static let retryDelays: [Duration] = [.seconds(1), .seconds(3), .seconds(10)]
    /// Wake, unlock and display changes settle before the Dock is checked.
    static let settleAfterSessionChange: Duration = .seconds(1)

    // MARK: Permission

    /// How often AXIsProcessTrusted is re-read (§5.7).
    static let permissionCheckInterval: TimeInterval = 1
}
