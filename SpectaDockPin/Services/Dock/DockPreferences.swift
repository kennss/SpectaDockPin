//
//  @file        DockPreferences.swift
//  @description Reads the Dock settings that decide whether pinning applies (DESIGN §5.6): orientation,
//               autohide, bottom hot corners, and whether displays have separate Spaces.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//
//  Notes:
//  - Not sandboxed, so com.apple.dock is read directly (CFPreferencesAppSynchronize, then
//    CFPreferencesCopyAppValue). Values forced by a configuration profile come through the same call.
//  - `orientation` is absent on a Mac that never moved the Dock: absent means bottom (checked 2026-10-18).
//  - Hot corner values: 0 or 1 mean "none"; anything else is an action (14 = Quick Note).
//  - NSScreen.screensHaveSeparateSpaces is only right once NSApplication exists (§3 S5); this app always has
//    one by the time it reads it.
//

import AppKit

enum DockOrientation: String, Sendable {
    case bottom, left, right
}

struct DockSettings: Sendable, Equatable {
    var orientation: DockOrientation = .bottom
    var autohide = false
    var bottomLeftHotCorner = false
    var bottomRightHotCorner = false
    var separateSpaces = true
}

enum DockPreferences {
    /// A String, bridged to CFString at each call: a static CFString is not Sendable.
    private static let domain = "com.apple.dock"

    @MainActor
    static func read() -> DockSettings {
        CFPreferencesAppSynchronize(domain as CFString)
        var settings = DockSettings()
        if let raw = value("orientation") as? String {
            settings.orientation = DockOrientation(rawValue: raw) ?? .bottom
        }
        settings.autohide = (value("autohide") as? Bool) ?? false
        settings.bottomLeftHotCorner = isHotCorner(value("wvous-bl-corner"))
        settings.bottomRightHotCorner = isHotCorner(value("wvous-br-corner"))
        settings.separateSpaces = NSScreen.screensHaveSeparateSpaces
        return settings
    }

    private static func value(_ key: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, domain as CFString)
    }

    private static func isHotCorner(_ value: Any?) -> Bool {
        guard let action = (value as? NSNumber)?.intValue else { return false }
        return action > 1
    }
}
