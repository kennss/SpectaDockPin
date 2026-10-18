//
//  @file        SessionMonitor.swift
//  @description Turns sleep/wake, screen lock, fast user switching, Space changes and Dock relaunches into one
//               stream of SessionEvents for AppModel, and answers the session questions the RelocationPolicy
//               asks (DESIGN §5.5).
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//
//  Notes:
//  - Every signal goes to AppModel, which alone decides to check the Dock or start a relocation (unlike the
//    original DockAnchor, where each signal scheduled its own relocation).
//  - Locked = the last lock notification said so, or the session dictionary has CGSSessionScreenIsLocked
//    true. The key's presence while locked is still to be verified (T4), so both sources count.
//  - On console: kCGSessionOnConsoleKey, read fresh each time.
//

import AppKit
import CoreGraphics

enum SessionEvent: Sendable, Equatable {
    case willSleep
    case didWake
    case screenLocked
    case screenUnlocked
    case sessionResigned
    case sessionActivated
    case spaceChanged
    case dockRelaunched
}

@MainActor
final class SessionMonitor {
    var onEvent: ((SessionEvent) -> Void)?

    private(set) var isAsleep = false
    private var lockedByNotification = false
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    func start() {
        guard tokens.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { $0.isAsleep = true; $0.emit(.willSleep) }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.isAsleep = false; $0.emit(.didWake) }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.emit(.didWake) }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.emit(.sessionResigned) }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.emit(.sessionActivated) }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { $0.emit(.spaceChanged) }
        let launched = workspace.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil,
                                             queue: .main) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                if bundleID == DockLocator.dockBundleID { self?.emit(.dockRelaunched) }
            }
        }
        tokens.append((workspace, launched))

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) {
            $0.lockedByNotification = true
            $0.emit(.screenLocked)
        }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) {
            $0.lockedByNotification = false
            $0.emit(.screenUnlocked)
        }
        lockedByNotification = Self.sessionDictionary()["CGSSessionScreenIsLocked"].flatMap(Self.bool) ?? false
    }

    func stop() {
        for (center, token) in tokens { center.removeObserver(token) }
        tokens.removeAll()
    }

    var isScreenLocked: Bool {
        lockedByNotification || (Self.sessionDictionary()["CGSSessionScreenIsLocked"].flatMap(Self.bool) ?? false)
    }

    var isOnConsole: Bool {
        Self.sessionDictionary()[kCGSessionOnConsoleKey as String].flatMap(Self.bool) ?? true
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ handler: @escaping @MainActor (SessionMonitor) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self)
            }
        }
        tokens.append((center, token))
    }

    private func emit(_ event: SessionEvent) {
        AppLog.session.info("\(String(describing: event), privacy: .public)")
        onEvent?(event)
    }

    private static func sessionDictionary() -> [String: Any] {
        CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
    }

    private static func bool(_ value: Any) -> Bool? {
        (value as? NSNumber)?.boolValue
    }
}
