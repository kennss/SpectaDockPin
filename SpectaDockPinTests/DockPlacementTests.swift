//
//  @file        DockPlacementTests.swift
//  @description DockLocator.placement: the Dock window matches a display exactly (F8), within tolerance, by
//               largest overlap, or not at all (DESIGN §5.3, §8). Also checks that the test host starts
//               nothing (I7).
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//
//  Run: xcodebuild test -project SpectaDockPin.xcodeproj -scheme SpectaDockPin -only-testing:SpectaDockPinTests/DockPlacementTests
//

import CoreGraphics
import Testing
@testable import SpectaDockPin

private let lg = DisplayInfo(id: 3, uuid: "lg", name: "LG", bounds: CGRect(x: 0, y: 0, width: 3008, height: 1692), isMain: true)
private let dell = DisplayInfo(id: 4, uuid: "dell", name: "Dell", bounds: CGRect(x: 3008, y: 0, width: 2560, height: 1440), isMain: false)
private let displays = [lg, dell]

struct DockPlacementTests {
    @Test func exactBoundsPickThatDisplay() {
        #expect(DockLocator.placement(of: lg.bounds, in: displays) == .display(lg.id))
        #expect(DockLocator.placement(of: dell.bounds, in: displays) == .display(dell.id))
    }

    @Test func withinOnePointStillMatches() {
        let nearly = CGRect(x: 3008.5, y: 0, width: 2559.5, height: 1440.8)
        #expect(DockLocator.placement(of: nearly, in: displays) == .display(dell.id))
    }

    @Test func otherwiseTheLargestOverlapWins() {
        let straddling = CGRect(x: 2000, y: 100, width: 2000, height: 500)   // 1008 on LG, 992 on Dell
        #expect(DockLocator.placement(of: straddling, in: displays) == .display(lg.id))
    }

    @Test func noOverlapIsUnknown() {
        #expect(DockLocator.placement(of: CGRect(x: -5000, y: 0, width: 100, height: 100), in: displays) == .unknown)
        #expect(DockLocator.placement(of: lg.bounds, in: []) == .unknown)
    }

    @Test @MainActor func testHostStartsNothing() {
        #expect(AppRuntime.isUnitTestHost)
        let model = AppModel()
        model.start()
        #expect(!model.started)
        #expect(model.status == .starting)
    }
}
