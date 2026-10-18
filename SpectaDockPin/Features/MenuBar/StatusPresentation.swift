//
//  @file        StatusPresentation.swift
//  @description How each PinStatus reads in the menu and looks in the menu bar (DESIGN §6). All user-facing
//               text goes through the String Catalog.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//
//  Notes:
//  - Menu bar symbols are monochrome templates (DESIGN §7 brand): pinned dock.rectangle, moving
//    dock.arrow.down.rectangle, moved by the user dock.arrow.up.rectangle, paused pause.circle, needs
//    attention exclamationmark.triangle (all present on macOS 14+, checked 2026-10-18).
//

import Foundation

extension PinStatus {
    var symbolName: String {
        switch self {
        case .pinned, .starting: "dock.rectangle"
        case .dockAway, .relocating, .waiting, .retrying: "dock.arrow.down.rectangle"
        case .movedByUser: "dock.arrow.up.rectangle"
        case .paused: "pause.circle"
        case .needsPermission, .failed, .dockNotFound: "exclamationmark.triangle"
        }
    }

    var headline: String {
        switch self {
        case .starting:
            String(localized: "Starting…")
        case .needsPermission:
            String(localized: "Needs permission to guard the Dock")
        case .paused(let reason):
            reason.headline
        case .pinned(let anchorName):
            String(localized: "Dock pinned to \(anchorName)")
        case .movedByUser(let displayName):
            String(localized: "Dock moved with Option to \(displayName)")
        case .dockAway(let displayName):
            String(localized: "Dock is on \(displayName) — moving it back")
        case .waiting(let reason):
            reason.headline
        case .relocating:
            String(localized: "Moving the Dock back…")
        case .retrying(let attempt):
            String(localized: "Dock didn't move back — trying again (attempt \(attempt))")
        case .failed(let attempts):
            String(localized: "Dock didn't move back after \(attempts) tries")
        case .dockNotFound:
            String(localized: "Can't find the Dock")
        }
    }
}

extension PauseReason {
    var headline: String {
        switch self {
        case .userPaused:
            String(localized: "Paused")
        case .singleDisplay:
            String(localized: "Paused — only one display")
        case .dockOnSide(.left):
            String(localized: "Paused — Dock is on the left")
        case .dockOnSide(.right):
            String(localized: "Paused — Dock is on the right")
        case .dockOnSide(.bottom):
            String(localized: "Paused")
        case .sharedSpaces:
            String(localized: "Paused — “Displays have separate Spaces” is off")
        }
    }
}

extension WaitReason {
    var headline: String {
        switch self {
        case .noPermission: String(localized: "Waiting for permission")
        case .paused: String(localized: "Paused")
        case .userOverride: String(localized: "Dock moved with Option")
        case .asleep: String(localized: "Waiting — the Mac is asleep")
        case .screenLocked: String(localized: "Waiting — the screen is locked")
        case .notOnConsole: String(localized: "Waiting — another user is active")
        case .buttonDown: String(localized: "Waiting — a mouse button is down")
        case .userActive: String(localized: "Waiting for the pointer to rest")
        }
    }
}
