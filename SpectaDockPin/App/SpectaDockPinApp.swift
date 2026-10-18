//
//  @file        SpectaDockPinApp.swift
//  @description SwiftUI entry point: a menu-bar-only app (LSUIElement) with one MenuBarExtra.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//
//  Notes:
//  - AppModel is owned by AppDelegate (not @State here) so its start() and shutdown() run exactly at launch
//    and quit; the scene only reads it.
//

import SwiftUI

@main
struct SpectaDockPinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appDelegate.model)
        } label: {
            MenuBarLabel(model: appDelegate.model)
        }
        .menuBarExtraStyle(.menu)
    }
}
