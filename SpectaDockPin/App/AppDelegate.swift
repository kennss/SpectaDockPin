//
//  @file        AppDelegate.swift
//  @description Owns the AppModel and the Sparkle updater and ties them to the app's lifetime: start at
//               launch, shut down (tap first) at quit.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-19
//

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let updater = UpdaterController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }
}
