//
//  @file        LoginItem.swift
//  @description "Launch at login": registers SpectaDockPin as the user's login item (SMAppService.mainApp).
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//
//  Notes:
//  - Off by default and only turned on by the user (SpectArk rule, DESIGN §6): macOS announces every new
//    login item.
//  - `status` can change behind our back (System Settings ▸ General ▸ Login Items), so the menu re-reads it
//    each time it opens.
//  - `.requiresApproval`: registered, but switched off in System Settings; only the user can switch it back.
//  - A unit-test host never registers anything (AppRuntime, I7).
//

import ServiceManagement

@MainActor
@Observable
final class LoginItem {
    private(set) var status: SMAppService.Status = SMAppService.mainApp.status
    /// The last attempt to change it failed.
    private(set) var lastError: String?

    var isEnabled: Bool { status == .enabled }
    var needsApproval: Bool { status == .requiresApproval }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        guard !AppRuntime.isUnitTestHost else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
