//
//  @file        DisplayMapTests.swift
//  @description DisplayMap geometry: anchor choice and fallback, trigger rows per arrangement, the stretches
//               left out above another display, and the relocation point (DESIGN §5.1, §8).
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//
//  Run: xcodebuild test -project SpectaDockPin.xcodeproj -scheme SpectaDockPin -only-testing:SpectaDockPinTests/DisplayMapTests
//

import CoreGraphics
import Testing
@testable import SpectaDockPin

private func display(_ id: CGDirectDisplayID, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                     main: Bool = false) -> DisplayInfo {
    DisplayInfo(id: id, uuid: "uuid-\(id)", name: "D\(id)", bounds: CGRect(x: x, y: y, width: w, height: h), isMain: main)
}

/// Kennt's desk (DESIGN §3): LG main in the middle, MacBook left, Dell right, tops aligned.
private let lg = display(3, 0, 0, 3008, 1692, main: true)
private let macBook = display(1, -1728, 0, 1728, 1117)
private let dell = display(4, 3008, 0, 2560, 1440)
private let desk = [lg, macBook, dell]

struct DisplayMapTests {
    @Test func anchorDefaultsToTheMainDisplay() {
        let map = DisplayMap(displays: desk, preferredAnchorUUID: nil)
        #expect(map.anchor?.id == lg.id)
        #expect(!map.anchorIsFallback)
    }

    @Test func chosenAnchorIsUsedWhenConnected() {
        let map = DisplayMap(displays: desk, preferredAnchorUUID: dell.uuid)
        #expect(map.anchor?.id == dell.id)
        #expect(map.triggerStrips().contains(CGRect(x: 0, y: 1691, width: 3008, height: 1)))
    }

    @Test func missingChosenAnchorFallsBackToMain() {
        let map = DisplayMap(displays: desk, preferredAnchorUUID: "not-connected")
        #expect(map.anchor?.id == lg.id)
        #expect(map.anchorIsFallback)
    }

    @Test func sideBySideGuardsTheLastRowOfEveryOtherDisplay() {
        let strips = DisplayMap(displays: desk, preferredAnchorUUID: nil).triggerStrips()
        #expect(Set(strips.map(\.debugDescription)) == Set([
            CGRect(x: -1728, y: 1116, width: 1728, height: 1),
            CGRect(x: 3008, y: 1439, width: 2560, height: 1),
        ].map(\.debugDescription)))
    }

    @Test func relocationPointIsTheMiddleOfTheAnchorsLastRow() {
        #expect(DisplayMap(displays: desk, preferredAnchorUUID: nil).relocationPoint == CGPoint(x: 1504, y: 1691))
    }

    @Test func userOverrideDisplayIsLeftUnguarded() {
        let strips = DisplayMap(displays: desk, preferredAnchorUUID: nil).triggerStrips(alsoExcluding: dell.id)
        #expect(strips == [CGRect(x: -1728, y: 1116, width: 1728, height: 1)])
    }

    @Test func stackedDisplayAboveIsNotGuardedWhereTheLowerOneTouches() {
        // Main on top, a wider display below: the top display's whole bottom edge is a passage.
        let top = display(1, 0, 0, 1920, 1080, main: true)
        let bottom = display(2, -320, 1080, 2560, 1440)
        let map = DisplayMap(displays: [top, bottom], preferredAnchorUUID: bottom.uuid)
        #expect(map.triggerStrips().isEmpty)
        #expect(map.relocationPoint == CGPoint(x: 960, y: 2519))
    }

    @Test func partlyCoveredBottomEdgeKeepsOnlyTheFreeStretches() {
        // A narrower display below the middle of the main display.
        let main = display(1, 0, 0, 3000, 1000, main: true)
        let below = display(2, 1000, 1000, 1000, 800)
        let map = DisplayMap(displays: [main, below], preferredAnchorUUID: below.uuid)
        #expect(map.triggerStrips() == [
            CGRect(x: 0, y: 999, width: 1000, height: 1),
            CGRect(x: 2000, y: 999, width: 1000, height: 1),
        ])
    }

    @Test func relocationPointUsesTheLongestFreeStretch() {
        let main = display(1, 0, 0, 3000, 1000, main: true)
        let below = display(2, 500, 1000, 1000, 800)   // free: [0, 500) and [1500, 3000)
        let map = DisplayMap(displays: [main, below], preferredAnchorUUID: nil)
        #expect(map.relocationPoint == CGPoint(x: 2250, y: 999))
    }

    @Test func staircaseDisplaysEachKeepTheirOwnRow() {
        let main = display(1, 0, 0, 1920, 1080, main: true)
        let lower = display(2, 1920, 300, 1920, 1080)   // bottom at 1380, nothing below it
        let map = DisplayMap(displays: [main, lower], preferredAnchorUUID: nil)
        #expect(map.triggerStrips() == [CGRect(x: 1920, y: 1379, width: 1920, height: 1)])
    }

    @Test func singleDisplayHasNothingToGuard() {
        let map = DisplayMap(displays: [lg], preferredAnchorUUID: nil)
        #expect(map.triggerStrips().isEmpty)
        #expect(map.relocationPoint == CGPoint(x: 1504, y: 1691))
    }

    @Test func noDisplaysMeansNoAnchor() {
        #expect(DisplayMap.empty.anchor == nil)
        #expect(DisplayMap.empty.relocationPoint == nil)
    }
}
