//
//  @file        UpdaterController.swift
//  @description Sparkle auto-update (DESIGN §9): checks the GitHub Releases appcast of kennss/SpectaDockPin
//               for newer signed + notarized builds and installs them in place. Config (SUFeedURL,
//               SUPublicEDKey, SUEnableAutomaticChecks) is in Info.plist; updates are verified against the
//               Calida Lab EdDSA key shared with SpectArk and SiliconScope (private half in the login keychain).
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-19
//  @lastUpdated 2026-10-19
//
//  Notes:
//  - Only active in a real .app bundle that is not a unit-test host (I7); otherwise inert and the menu
//    item is disabled (SpectArk rule).
//  - SpectaDockPin is a menu-bar-only app (LSUIElement), so a scheduled check must not throw a window in the
//    user's face. It uses Sparkle's "gentle reminders": when an update is found while the app is not in
//    focus, Sparkle shows nothing and the menu gets an "Update Available…" item instead. Anything the user
//    started (Check for Updates…, Update Available…) brings the app forward so Sparkle's window is seen.
//

import AppKit
import Sparkle

@MainActor
@Observable
final class UpdaterController: NSObject {
    /// True only in the packaged .app, where Sparkle can actually run.
    let canCheck: Bool
    /// A scheduled check found an update the user has not looked at yet.
    private(set) var updateAvailable = false

    @ObservationIgnored private var controller: SPUStandardUpdaterController?

    override init() {
        canCheck = Bundle.main.bundleURL.pathExtension == "app" && !AppRuntime.isUnitTestHost
        super.init()
        if canCheck {
            controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
                                                      userDriverDelegate: self)
        }
    }

    /// "Check for Updates…" and "Update Available…".
    func checkForUpdates() {
        NSApp.activate()
        controller?.updater.checkForUpdates()
    }
}

extension UpdaterController: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        let userInitiated = state.userInitiated
        MainActor.assumeIsolated {
            if handleShowingUpdate {
                NSApp.activate()
            } else if !userInitiated {
                updateAvailable = true
            }
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { updateAvailable = false }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { updateAvailable = false }
    }
}
