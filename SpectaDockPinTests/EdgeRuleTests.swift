//
//  @file        EdgeRuleTests.swift
//  @description EdgeRule verdicts at the trigger-row boundaries, the corner pixels (F23), the app's own
//               events, Option, and an inactive snapshot (DESIGN §5.2, §8).
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//
//  Run: xcodebuild test -project SpectaDockPin.xcodeproj -scheme SpectaDockPin -only-testing:SpectaDockPinTests/EdgeRuleTests
//

import CoreGraphics
import Testing
@testable import SpectaDockPin

/// Dell's trigger row on Kennt's desk (DESIGN §3).
private let dellRow = CGRect(x: 3008, y: 1439, width: 2560, height: 1)
private let active = GuardSnapshot(isActive: true, strips: [dellRow])

private func verdict(_ x: CGFloat, _ y: CGFloat, option: Bool = false, own: Bool = false,
                     snapshot: GuardSnapshot = active) -> EdgeVerdict {
    EdgeRule.verdict(at: CGPoint(x: x, y: y), optionDown: option, isOwnEvent: own, snapshot: snapshot)
}

struct EdgeRuleTests {
    @Test(arguments: [1439.0, 1439.5, 1439.99])
    func lastRowIsDropped(y: CGFloat) {
        #expect(verdict(4000, y) == .drop)
    }

    @Test(arguments: [1438.99, 1438.0, 1435.0, 0.0])
    func rowsAboveAreDelivered(y: CGFloat) {
        #expect(verdict(4000, y) == .pass)
    }

    @Test(arguments: [3008.0, 3008.5, 5567.0, 5567.9])
    func cornerPixelsAreDroppedToo(x: CGFloat) {
        #expect(verdict(x, 1439) == .drop)
    }

    @Test func otherDisplaysAreDelivered() {
        #expect(verdict(1504, 1691) == .pass)     // the anchor's row
        #expect(verdict(5568, 1439) == .pass)     // just past Dell's right edge
        #expect(verdict(3007.9, 1439) == .pass)   // LG, left of Dell
    }

    @Test func optionLetsTheEventThrough() {
        #expect(verdict(4000, 1439, option: true) == .passOption)
    }

    @Test func ownEventsPassEvenWithOption() {
        #expect(verdict(4000, 1439, option: true, own: true) == .passOwn)
    }

    @Test func inactiveSnapshotDropsNothing() {
        #expect(verdict(4000, 1439, snapshot: .inactive) == .pass)
        #expect(verdict(4000, 1439, snapshot: GuardSnapshot(isActive: false, strips: [dellRow])) == .pass)
    }
}
