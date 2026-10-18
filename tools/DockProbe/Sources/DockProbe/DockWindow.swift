//
//  @file        DockWindow.swift
//  @description Finds the Dock's window and the display it is on, the way the app's DockLocator will
//               (DESIGN §5.3): by Dock PID + window layer, never by window or owner name.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//
//  Key declared values:
//  - dockLayer: CGWindowLevelForKey(.dockWindow), 20 on macOS 27 (§3 F8).
//  - The Dock window's bounds equal the bounds of the display it is on (§3 F8), so placement is an
//    exact match with 1-pt tolerance, then the largest overlap, then unknown.
//  - While moving, the Dock owns a second layer-20 window for ~0.1–0.25 s ("DockClone", old bounds, listed
//    first; §3 F15). Names are unreadable in the sandbox (§3 F7), so a scan waits for a single candidate.
//  - The window number is cached and normally re-read alone with CGWindowListCreateDescriptionFromArray.
//    That API takes a CFArray of raw CGWindowID values (not CFNumbers), built with NULL callbacks.
//

import AppKit
import CoreGraphics

struct DockWindowInfo: Sendable, Equatable {
    let pid: pid_t
    let windowID: CGWindowID
    let layer: Int
    /// CG global bounds in points.
    let bounds: CGRect
    let isOnScreen: Bool
}

enum DockPlacement: Sendable, Equatable {
    case display(index: Int)
    case unknown
}

@MainActor
final class DockLocator {
    static let dockBundleID = "com.apple.dock"
    static let dockLayer = Int(CGWindowLevelForKey(.dockWindow))
    /// The move clone lived 0.10–0.25 s in §3 F15; give a scan up to 1 s to see a single window.
    static let settleTimeout: TimeInterval = 1.0
    static let settleInterval: useconds_t = 20_000

    private var cached: DockWindowInfo?
    /// How many full window-list scans have run (a cache miss each time after the first).
    private(set) var fullScans = 0

    /// The Dock's window, from the cached window number when it is still valid.
    func current() -> DockWindowInfo? {
        if let cached, let fresh = Self.describe(windowID: cached.windowID, expectedPID: cached.pid) {
            self.cached = fresh
            return fresh
        }
        fullScans += 1
        cached = Self.scan()
        return cached
    }

    static func dockPID() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: dockBundleID).first?.processIdentifier
    }

    /// Full scan of the window list for the Dock-owned window at the Dock layer. While the Dock moves it
    /// briefly owns a second window at the same layer (a clone with the OLD bounds, listed first; §3 F15),
    /// so a scan only answers when exactly one candidate exists, re-reading for up to `settleTimeout`.
    static func scan() -> DockWindowInfo? {
        guard let pid = dockPID() else { return nil }
        let start = ProcessInfo.processInfo.systemUptime
        while true {
            let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
            let candidates = list.compactMap { info(from: $0) }.filter { $0.pid == pid && $0.layer == dockLayer }
            if candidates.count <= 1 { return candidates.first }
            if ProcessInfo.processInfo.systemUptime - start >= settleTimeout { return nil }
            usleep(settleInterval)
        }
    }

    /// Re-reads one window. Nil when it is gone or no longer the Dock's.
    static func describe(windowID: CGWindowID, expectedPID: pid_t) -> DockWindowInfo? {
        var value = UnsafeRawPointer(bitPattern: UInt(windowID))
        guard let array = CFArrayCreate(nil, &value, 1, nil),
              let list = CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]],
              let first = list.first,
              let info = info(from: first),
              info.pid == expectedPID, info.layer == dockLayer
        else { return nil }
        return info
    }

    private static func info(from window: [String: Any]) -> DockWindowInfo? {
        guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
              let number = window[kCGWindowNumber as String] as? CGWindowID,
              let layer = window[kCGWindowLayer as String] as? Int,
              let boundsDict = window[kCGWindowBounds as String],
              let bounds = CGRect(dictionaryRepresentation: boundsDict as! CFDictionary)
        else { return nil }
        let onScreen = (window[kCGWindowIsOnscreen as String] as? Bool) ?? false
        return DockWindowInfo(pid: pid, windowID: number, layer: layer, bounds: bounds, isOnScreen: onScreen)
    }

    /// Which display the Dock window is on.
    nonisolated static func placement(of bounds: CGRect, in displays: [DisplayInfo]) -> DockPlacement {
        let tolerance: CGFloat = 1
        if let exact = displays.firstIndex(where: {
            abs($0.bounds.minX - bounds.minX) <= tolerance && abs($0.bounds.minY - bounds.minY) <= tolerance
                && abs($0.bounds.width - bounds.width) <= tolerance && abs($0.bounds.height - bounds.height) <= tolerance
        }) {
            return .display(index: exact)
        }
        let overlaps = displays.enumerated().map { index, display -> (Int, CGFloat) in
            let cut = display.bounds.intersection(bounds)
            return (index, cut.isNull ? 0 : cut.width * cut.height)
        }
        if let best = overlaps.max(by: { $0.1 < $1.1 }), best.1 > 0 { return .display(index: best.0) }
        return .unknown
    }
}
