//
//  @file        AppSettings.swift
//  @description The user's choices, persisted in UserDefaults: which display the Dock is pinned to and
//               whether pinning is paused.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//
//  Key declared values:
//  - Keys carry the `spectadockpin.` prefix and are never renamed once shipped (DESIGN §7).
//  - anchorDisplayUUID: CGDisplayCreateUUIDFromDisplayID string; nil means "the main display". A UUID whose
//    display is not connected falls back to the main display without being forgotten (DESIGN §6).
//

import Foundation

@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let anchorDisplayUUID = "spectadockpin.anchorDisplayUUID"
        static let paused = "spectadockpin.paused"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var anchorDisplayUUID: String? {
        didSet { defaults.set(anchorDisplayUUID, forKey: Key.anchorDisplayUUID) }
    }

    var paused: Bool {
        didSet { defaults.set(paused, forKey: Key.paused) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        anchorDisplayUUID = defaults.string(forKey: Key.anchorDisplayUUID)
        paused = defaults.bool(forKey: Key.paused)
    }
}
