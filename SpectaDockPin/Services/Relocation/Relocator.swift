//
//  @file        Relocator.swift
//  @description Calls the Dock back to the anchor by moving the real pointer down onto the anchor's last row,
//               then puts the pointer back (DESIGN §5.4 steps 3–4). One drive per call; the caller decides
//               when to drive and when to retry.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//
//  Notes:
//  - Moving the real pointer is the only way (F6). Events go to the HID level, stamped with
//    EdgeRule.ownEventMarker so the guard lets them through and they are not mistaken for the user.
//  - The approach starts approachHeight above the row and comes down approachStep per event. Posting straight
//    onto the row fails for minutes after the pointer left the Dock by warp (F16); the approach always worked.
//  - Only mouseMoved is posted, never a drag (F10).
//  - The pointer is put back with a posted mouseMoved, not CGWarpMouseCursorPosition: a warp leaves the Dock
//    believing the pointer is still over it (F16) and briefly freezes real mouse input.
//  - Any real pointer event during the drive (EdgeGuard.status.lastUserPointerEvent) ends it at once, and the
//    pointer is then left where the user has it.
//  - Cancelling the task (lock, sleep, quit) ends the drive and still puts the pointer back.
//  - The cursor is not hidden: that needs a private API for an app in the background.
//

import CoreGraphics
import Foundation

enum DriveOutcome: Sendable, Equatable {
    /// The Dock arrived on the anchor after this many seconds.
    case arrived(TimeInterval)
    /// It did not arrive within relocationTimeout on the row.
    case timedOut
    /// The user moved the pointer during the drive.
    case abortedByUser
    /// The task was cancelled (lock, sleep, quit).
    case cancelled
}

@MainActor
final class Relocator {
    private let locator: DockLocator
    private let edgeGuard: EdgeGuard

    init(locator: DockLocator, edgeGuard: EdgeGuard) {
        self.locator = locator
        self.edgeGuard = edgeGuard
    }

    /// - Parameters:
    ///   - target: a point on the anchor's last row (DisplayMap.relocationPoint).
    ///   - isOnAnchor: whether a Dock window with the given bounds is on the anchor.
    func drive(to target: CGPoint, isOnAnchor: (CGRect) -> Bool) async -> DriveOutcome {
        guard !AppRuntime.isUnitTestHost else { return .cancelled }
        let saved = CGEvent(source: nil)?.location ?? target
        let start = ProcessInfo.processInfo.systemUptime
        var position = CGPoint(x: target.x, y: target.y - PinTuning.approachHeight)
        var reachedRowAt: TimeInterval?
        AppLog.relocate.info("drive to (\(target.x), \(target.y)) from (\(saved.x), \(saved.y))")

        var outcome = DriveOutcome.timedOut
        while true {
            if Task.isCancelled { outcome = .cancelled; break }
            Self.post(position, deltaY: position.y < target.y ? PinTuning.approachStep : 0)
            try? await Task.sleep(for: PinTuning.driveInterval)

            if edgeGuard.status.lastUserPointerEvent > start {
                outcome = .abortedByUser
                break
            }
            if let dock = await locator.current(), isOnAnchor(dock.bounds) {
                outcome = .arrived(ProcessInfo.processInfo.systemUptime - start)
                break
            }
            let now = ProcessInfo.processInfo.systemUptime
            if position.y >= target.y {
                if reachedRowAt == nil { reachedRowAt = now }
                if let reachedRowAt, now - reachedRowAt >= PinTuning.relocationTimeout { break }
            }
            position.y = min(position.y + PinTuning.approachStep, target.y)
        }

        if outcome != .abortedByUser { Self.post(saved, deltaY: 0) }
        AppLog.relocate.info("drive ended: \(String(describing: outcome), privacy: .public)")
        return outcome
    }

    private static func post(_ location: CGPoint, deltaY: CGFloat) {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                  mouseCursorPosition: location, mouseButton: .left) else { return }
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(deltaY.rounded()))
        event.setIntegerValueField(.eventSourceUserData, value: EdgeRule.ownEventMarker)
        event.post(tap: .cghidEventTap)
    }
}
