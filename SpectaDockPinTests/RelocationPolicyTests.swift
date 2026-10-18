//
//  @file        RelocationPolicyTests.swift
//  @description RelocationPolicy: the cursor moves only when nothing in I3 holds, and each condition gives its
//               own wait reason, checked in priority order (DESIGN §5.4, §8).
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//
//  Run: xcodebuild test -project SpectaDockPin.xcodeproj -scheme SpectaDockPin -only-testing:SpectaDockPinTests/RelocationPolicyTests
//

import Foundation
import Testing
@testable import SpectaDockPin

private let clear = RelocationInputs(hasPermission: true, paused: false, userOverride: false, asleep: false,
                                     screenLocked: false, onConsole: true, buttonDown: false, secondsSinceInput: 5)

struct RelocationPolicyTests {
    @Test func goesWhenNothingHolds() {
        #expect(RelocationPolicy.decide(clear) == .go)
    }

    /// One I3 condition switched on, with the reason it must give.
    enum Condition: CaseIterable, Sendable {
        case noPermission, paused, userOverride, asleep, screenLocked, notOnConsole, buttonDown

        func apply(to inputs: inout RelocationInputs) {
            switch self {
            case .noPermission: inputs.hasPermission = false
            case .paused: inputs.paused = true
            case .userOverride: inputs.userOverride = true
            case .asleep: inputs.asleep = true
            case .screenLocked: inputs.screenLocked = true
            case .notOnConsole: inputs.onConsole = false
            case .buttonDown: inputs.buttonDown = true
            }
        }

        var reason: WaitReason {
            switch self {
            case .noPermission: .noPermission
            case .paused: .paused
            case .userOverride: .userOverride
            case .asleep: .asleep
            case .screenLocked: .screenLocked
            case .notOnConsole: .notOnConsole
            case .buttonDown: .buttonDown
            }
        }
    }

    @Test(arguments: Condition.allCases)
    func eachConditionWaits(condition: Condition) {
        var inputs = clear
        condition.apply(to: &inputs)
        #expect(RelocationPolicy.decide(inputs) == .wait(condition.reason))
    }

    @Test func recentInputWaits() {
        var inputs = clear
        inputs.secondsSinceInput = PinTuning.idleBeforeRelocation - 0.01
        #expect(RelocationPolicy.decide(inputs) == .wait(.userActive))
        inputs.secondsSinceInput = PinTuning.idleBeforeRelocation
        #expect(RelocationPolicy.decide(inputs) == .go)
    }

    @Test func lockedWinsOverABusyPointer() {
        var inputs = clear
        inputs.screenLocked = true
        inputs.buttonDown = true
        inputs.secondsSinceInput = 0
        #expect(RelocationPolicy.decide(inputs) == .wait(.screenLocked))
    }

    @Test func onlyPointerConditionsAreWorthPolling() {
        #expect(WaitReason.userActive.isShortLived)
        #expect(WaitReason.buttonDown.isShortLived)
        #expect(!WaitReason.screenLocked.isShortLived)
        #expect(!WaitReason.paused.isShortLived)
    }
}
