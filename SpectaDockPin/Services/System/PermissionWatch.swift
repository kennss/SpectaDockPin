//
//  @file        PermissionWatch.swift
//  @description Tracks the Accessibility grant the guard and the Relocator need, and asks for it
//               (DESIGN §5.7).
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//
//  Notes:
//  - AXIsProcessTrusted is re-read every permissionCheckInterval, plus soon after the distributed
//    notification "com.apple.accessibility.api" (its name is still to be verified, T6 — the timer alone is
//    enough).
//  - On a loss AppModel stops the tap before anything else (I4): a dropping tap that outlives its grant has
//    been reported to freeze all input (§12).
//  - macOS 27 calls the pane "Device Control and Data Access"; names differ between versions, so the UI
//    describes the setting instead of naming the pane (S8).
//

import AppKit
import ApplicationServices

@MainActor
final class PermissionWatch {
    /// x-apple.systempreferences URL that opens the Accessibility pane on macOS 14–27 (S8).
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    private(set) var isTrusted = AXIsProcessTrusted()
    var onChange: ((Bool) -> Void)?

    private var task: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(PinTuning.permissionCheckInterval))
                self?.recheck()
            }
        }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.recheckSoon()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
    }

    func recheck() {
        let trusted = AXIsProcessTrusted()
        guard trusted != isTrusted else { return }
        isTrusted = trusted
        AppLog.permission.notice("accessibility trusted: \(trusted)")
        onChange?(trusted)
    }

    /// Shows the system prompt (which also lists the app in the pane) and opens the pane.
    func request() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(Self.settingsURL)
    }

    private func recheckSoon() {
        Task { [weak self] in
            // The grant is written just after the notification; read it a moment later.
            try? await Task.sleep(for: .milliseconds(200))
            self?.recheck()
        }
    }
}
