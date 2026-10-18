//
//  @file        DockLocator.swift
//  @description Finds the Dock's window and the display it is on (DESIGN §5.3): by Dock PID + window layer,
//               never by window or owner name.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//
//  Notes:
//  - The Dock window's bounds equal the bounds of the display it is on (F8). Placement: exact match within
//    placementTolerance, then the largest overlap, then unknown.
//  - The window number is cached and normally re-read alone with CGWindowListCreateDescriptionFromArray
//    (F14). That API takes a CFArray of raw CGWindowID values, not CFNumbers, built with NULL callbacks.
//  - While moving, the Dock owns a second layer-20 window for 0.10–0.25 s (F15, "DockClone", old bounds,
//    listed first). A full scan therefore only answers once a single candidate is left, re-reading every
//    dockSettleInterval for up to dockSettleTimeout (async, so the main thread keeps running).
//  - `isOnscreen` is not a condition: it is false with autohide or a full-screen app on the anchor (F20, F21).
//  - The Dock restarting changes both its PID and its window number (F21); a stale cache simply misses and
//    the next scan finds the new window.
//
//  Key declared values:
//  - dockLayer: CGWindowLevelForKey(.dockWindow), 20 on macOS 27 (F8).
//

import AppKit
import CoreGraphics

enum DockPlacement: Sendable, Equatable {
    case display(CGDirectDisplayID)
    case unknown
}

struct DockWindowInfo: Sendable, Equatable {
    let pid: pid_t
    let windowID: CGWindowID
    /// CG global bounds in points.
    let bounds: CGRect
}

@MainActor
final class DockLocator {
    static let dockBundleID = "com.apple.dock"
    static let dockLayer = Int(CGWindowLevelForKey(.dockWindow))

    private var cached: DockWindowInfo?

    /// The Dock's window now, or nil when there is none or it stayed ambiguous.
    func current() async -> DockWindowInfo? {
        if let cached, let fresh = Self.describe(windowID: cached.windowID, expectedPID: cached.pid) {
            self.cached = fresh
            return fresh
        }
        cached = await scan()
        return cached
    }

    /// Forget the cached window (the Dock relaunched).
    func invalidate() {
        cached = nil
    }

    static func dockPID() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: dockBundleID).first?.processIdentifier
    }

    private func scan() async -> DockWindowInfo? {
        guard let pid = Self.dockPID() else { return nil }
        let start = ProcessInfo.processInfo.systemUptime
        while true {
            let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
            let candidates = list.compactMap(Self.info(from:)).filter { $0.pid == pid && $0.layer == Self.dockLayer }
            if candidates.count <= 1 { return candidates.first.map(\.window) }
            guard ProcessInfo.processInfo.systemUptime - start < PinTuning.dockSettleTimeout else {
                AppLog.dock.notice("still \(candidates.count) Dock windows after settle timeout")
                return nil
            }
            try? await Task.sleep(for: PinTuning.dockSettleInterval)
        }
    }

    private static func describe(windowID: CGWindowID, expectedPID: pid_t) -> DockWindowInfo? {
        var value = UnsafeRawPointer(bitPattern: UInt(windowID))
        guard let array = CFArrayCreate(nil, &value, 1, nil),
              let list = CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]],
              let first = list.first,
              let info = info(from: first),
              info.pid == expectedPID, info.layer == dockLayer
        else { return nil }
        return info.window
    }

    private static func info(from window: [String: Any]) -> (pid: pid_t, layer: Int, window: DockWindowInfo)? {
        guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
              let number = window[kCGWindowNumber as String] as? CGWindowID,
              let layer = window[kCGWindowLayer as String] as? Int,
              let boundsValue = window[kCGWindowBounds as String],
              CFGetTypeID(boundsValue as CFTypeRef) == CFDictionaryGetTypeID(),
              let bounds = CGRect(dictionaryRepresentation: boundsValue as! CFDictionary)
        else { return nil }
        return (pid, layer, DockWindowInfo(pid: pid, windowID: number, bounds: bounds))
    }

    /// Which display a Dock window with these bounds is on. Pure; unit-tested.
    nonisolated static func placement(of bounds: CGRect, in displays: [DisplayInfo]) -> DockPlacement {
        let tolerance = PinTuning.placementTolerance
        if let exact = displays.first(where: {
            abs($0.bounds.minX - bounds.minX) <= tolerance && abs($0.bounds.minY - bounds.minY) <= tolerance
                && abs($0.bounds.width - bounds.width) <= tolerance && abs($0.bounds.height - bounds.height) <= tolerance
        }) {
            return .display(exact.id)
        }
        let best = displays
            .map { display -> (CGDirectDisplayID, CGFloat) in
                let cut = display.bounds.intersection(bounds)
                return (display.id, cut.isNull ? 0 : cut.width * cut.height)
            }
            .max { $0.1 < $1.1 }
        if let best, best.1 > 0 { return .display(best.0) }
        return .unknown
    }
}
