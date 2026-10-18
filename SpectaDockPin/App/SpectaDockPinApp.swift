//
//  @file        SpectaDockPinApp.swift
//  @description SwiftUI entry point: a menu-bar-only app (LSUIElement) with one MenuBarExtra.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-19
//
//  Notes:
//  - AppModel and UpdaterController are owned by AppDelegate (not @State here) so start() and shutdown() run
//    exactly at launch and quit; the scene only reads them.
//

import SwiftUI

@main
struct SpectaDockPinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appDelegate.model)
                .environment(appDelegate.updater)
        } label: {
            MenuBarLabel(model: appDelegate.model)
        }
        .menuBarExtraStyle(.menu)
    }
}
