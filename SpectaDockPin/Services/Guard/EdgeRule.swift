//
//  @file        EdgeRule.swift
//  @description The guard's decision for one pointer event, as a pure function of the event and the current
//               GuardSnapshot (DESIGN §5.2). Runs on the tap thread for every pointer event — no allocation,
//               no system calls. Unit-tested.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//
//  Key declared values:
//  - ownEventMarker: eventSourceUserData stamped on every event the Relocator posts ("SPDP"), so the guard
//    and the user-input detector can tell them from real input.
//  - Order of the rule: inactive → pass; off the trigger rows → pass; own event → pass; Option held → pass
//    (DESIGN §13 decision 3: only the mouse event's own modifier flags are read, no keyboard monitoring);
//    otherwise drop.
//

import CoreGraphics

/// What the guard needs to decide, swapped as a whole whenever displays, the Dock or the settings change.
struct GuardSnapshot: Sendable, Equatable {
    /// False while paused, without permission, or in a pause condition (I6).
    var isActive: Bool
    /// 1-pt rows in CG global coordinates (DisplayMap.triggerStrips).
    var strips: [CGRect]

    static let inactive = GuardSnapshot(isActive: false, strips: [])
}

enum EdgeVerdict: Sendable, Equatable {
    /// Not a trigger: deliver.
    case pass
    /// On a trigger row: drop.
    case drop
    /// On a trigger row with Option held: deliver, and the Dock may follow (user override).
    case passOption
    /// Posted by the Relocator: deliver.
    case passOwn
}

enum EdgeRule {
    static let ownEventMarker: Int64 = 0x5350_4450

    static func verdict(at location: CGPoint, optionDown: Bool, isOwnEvent: Bool, snapshot: GuardSnapshot) -> EdgeVerdict {
        guard snapshot.isActive, snapshot.strips.contains(where: { $0.contains(location) }) else { return .pass }
        if isOwnEvent { return .passOwn }
        if optionDown { return .passOption }
        return .drop
    }
}
