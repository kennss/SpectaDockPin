//
//  @file        AppRuntime.swift
//  @description Facts about how this process was launched that change what the app may do at startup.
//               Today: whether it is the host app of a unit-test run (DESIGN I7).
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//
//  Notes:
//  - The unit tests are hosted by SpectaDockPin.app itself (TEST_HOST in project.yml), so every test run
//    launches the full app. A test host must create no event tap and never move the cursor: a dropping tap
//    left behind by a test run would eat the developer's pointer events.
//  - Xcode and xcodebuild put the XCTest configuration into the host app's environment; different Xcode
//    versions use different keys, so any of them counts (SpectArk precedent).
//

import Foundation

enum AppRuntime {
    /// True when this process hosts a unit-test run.
    static let isUnitTestHost: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"]
            .contains { environment[$0] != nil }
    }()
}
