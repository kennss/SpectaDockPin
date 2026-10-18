//
//  @file        RelocationPolicy.swift
//  @description Whether the Relocator may move the cursor right now (DESIGN §5.4 step 2, I3). Pure; unit-tested.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//
//  Notes:
//  - Reasons are checked from "never while this holds" to "soon": no permission, paused, the user moved the
//    Dock on purpose, the Mac is asleep, the screen is locked, the session is not on the console (fast user
//    switching), a mouse button is down (synthetic moves during a press can wedge the Dock, F10), the user
//    moved the pointer less than idleBeforeRelocation ago.
//  - Only the last two are worth waiting out; the others end the attempt until an event starts a new one.
//

import Foundation

struct RelocationInputs: Sendable, Equatable {
    var hasPermission: Bool
    var paused: Bool
    var userOverride: Bool
    var asleep: Bool
    var screenLocked: Bool
    var onConsole: Bool
    var buttonDown: Bool
    /// Seconds since the last real input of any kind.
    var secondsSinceInput: TimeInterval
}

enum WaitReason: Sendable, Equatable {
    case noPermission
    case paused
    case userOverride
    case asleep
    case screenLocked
    case notOnConsole
    case buttonDown
    case userActive

    /// The condition usually clears by itself within seconds, so the Relocator keeps polling.
    var isShortLived: Bool {
        switch self {
        case .buttonDown, .userActive: true
        default: false
        }
    }
}

enum RelocationDecision: Sendable, Equatable {
    case go
    case wait(WaitReason)
}

enum RelocationPolicy {
    static func decide(_ inputs: RelocationInputs) -> RelocationDecision {
        if !inputs.hasPermission { return .wait(.noPermission) }
        if inputs.paused { return .wait(.paused) }
        if inputs.userOverride { return .wait(.userOverride) }
        if inputs.asleep { return .wait(.asleep) }
        if inputs.screenLocked { return .wait(.screenLocked) }
        if !inputs.onConsole { return .wait(.notOnConsole) }
        if inputs.buttonDown { return .wait(.buttonDown) }
        if inputs.secondsSinceInput < PinTuning.idleBeforeRelocation { return .wait(.userActive) }
        return .go
    }
}
