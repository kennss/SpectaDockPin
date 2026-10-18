//
//  @file        EdgeGuard.swift
//  @description The event tap that drops pointer events on the trigger rows (DESIGN §5.2). It is created, run
//               and torn down on its own thread's run loop, so a busy main thread cannot get it disabled by
//               timeout (I5). The callback only copies the snapshot under a lock and calls EdgeRule.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//
//  Notes:
//  - Tap: .cgSessionEventTap + .headInsertEventTap + .defaultTap (F4); needs the Accessibility permission.
//    Events: mouseMoved and the three drag types only. Keyboard events are never requested.
//  - CF objects (CFMachPort, CFRunLoop, CFRunLoopSource) are not Sendable. They live in `handles`, an
//    OSAllocatedUnfairLock created with uncheckedState: only touched under that lock, and the calls made on
//    them from another thread (tapEnable, CFRunLoopRemoveSource, CFMachPortInvalidate, CFRunLoopStop) are
//    thread-safe.
//  - stop() disables the tap, removes its source, invalidates the port, then ends the thread — in that order,
//    before anything else when the Accessibility grant goes away (I4).
//  - Disabling our own tap also delivers .tapDisabledByUserInput (F13). The callback re-enables only while
//    the port is still in `handles`; stop() clears it first, so a tap being torn down stays off.
//  - Also recorded for the main side: the last real (unmarked) pointer event — the Relocator aborts when the
//    user moves the mouse — and the last Option pass-through, to recognise a Dock the user moved on purpose.
//

import CoreGraphics
import Foundation
import os

/// What the main side reads from the guard.
struct GuardStatus: Sendable, Equatable {
    /// Trigger-row events dropped since launch.
    var droppedEvents = 0
    /// Separate visits to a trigger row that had events dropped: one per "Dock jump stopped".
    var blockedVisits = 0
    var disabledByTimeout = 0
    var disabledByUserInput = 0
    /// ProcessInfo.systemUptime of the last pointer event not posted by this app.
    var lastUserPointerEvent: TimeInterval = 0
    /// Uptime and location of the last trigger-row event let through because Option was held.
    var lastOptionPass: (time: TimeInterval, location: CGPoint)?

    static func == (lhs: GuardStatus, rhs: GuardStatus) -> Bool {
        lhs.droppedEvents == rhs.droppedEvents && lhs.blockedVisits == rhs.blockedVisits
            && lhs.disabledByTimeout == rhs.disabledByTimeout && lhs.disabledByUserInput == rhs.disabledByUserInput
            && lhs.lastUserPointerEvent == rhs.lastUserPointerEvent
            && lhs.lastOptionPass?.time == rhs.lastOptionPass?.time
    }
}

private struct GuardState: Sendable {
    var snapshot = GuardSnapshot.inactive
    var status = GuardStatus()
    var droppingVisit = false
}

private struct TapHandles {
    var port: CFMachPort?
    var source: CFRunLoopSource?
    var runLoop: CFRunLoop?
}

final class EdgeGuard: Sendable {
    static let eventMask: CGEventMask = [
        CGEventType.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
    ].reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }

    private let state = OSAllocatedUnfairLock(initialState: GuardState())
    private let handles = OSAllocatedUnfairLock<TapHandles>(uncheckedState: TapHandles())
    private let finished = OSAllocatedUnfairLock<DispatchSemaphore?>(initialState: nil)

    var isRunning: Bool {
        handles.withLockUnchecked { $0.port != nil }
    }

    /// Creates the tap on a new thread. False when it could not be created (no Accessibility permission, F9).
    func start() -> Bool {
        guard !isRunning, !AppRuntime.isUnitTestHost else { return isRunning }
        let ready = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        let created = OSAllocatedUnfairLock(initialState: false)
        finished.withLock { $0 = done }

        let thread = Thread { [self] in
            guard let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: Self.eventMask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    return Unmanaged<EdgeGuard>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                ready.signal()
                done.signal()
                return
            }
            let source = CFMachPortCreateRunLoopSource(nil, port, 0)
            let runLoop = CFRunLoopGetCurrent()
            handles.withLockUnchecked { handles in
                handles.port = port
                handles.source = source
                handles.runLoop = runLoop
            }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            created.withLock { $0 = true }
            ready.signal()
            CFRunLoopRun()
            done.signal()
        }
        thread.name = "SpectaDockPin.EdgeGuard"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        let ok = created.withLock { $0 }
        if ok {
            AppLog.guardTap.info("tap started")
        } else {
            AppLog.guardTap.error("tap could not be created")
        }
        return ok
    }

    /// Disables and removes the tap, then ends its thread. Safe to call at any time, more than once.
    func stop() {
        let wasRunning = handles.withLockUnchecked { handles -> Bool in
            guard let port = handles.port else { return false }
            CGEvent.tapEnable(tap: port, enable: false)
            if let runLoop = handles.runLoop, let source = handles.source {
                CFRunLoopRemoveSource(runLoop, source, .commonModes)
            }
            CFMachPortInvalidate(port)
            if let runLoop = handles.runLoop { CFRunLoopStop(runLoop) }
            handles = TapHandles()
            return true
        }
        guard wasRunning else { return }
        if let done = finished.withLock({ $0 }) { _ = done.wait(timeout: .now() + 1) }
        AppLog.guardTap.info("tap stopped")
    }

    func update(_ snapshot: GuardSnapshot) {
        state.withLock { $0.snapshot = snapshot }
    }

    var status: GuardStatus {
        state.withLock { $0.status }
    }

    /// Safety net on top of the callback's own re-enable (§5.2). True when the tap had to be switched back on.
    func reenableIfDisabled() -> Bool {
        handles.withLockUnchecked { handles in
            guard let port = handles.port, !CGEvent.tapIsEnabled(tap: port) else { return false }
            CGEvent.tapEnable(tap: port, enable: true)
            return true
        }
    }

    /// Tap thread only.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let reenabled = handles.withLockUnchecked { handles -> Bool in
                guard let port = handles.port else { return false }
                CGEvent.tapEnable(tap: port, enable: true)
                return true
            }
            if reenabled {
                state.withLock { state in
                    if type == .tapDisabledByTimeout {
                        state.status.disabledByTimeout += 1
                    } else {
                        state.status.disabledByUserInput += 1
                    }
                }
            }
            return Unmanaged.passUnretained(event)
        }

        let location = event.location
        let isOwnEvent = event.getIntegerValueField(.eventSourceUserData) == EdgeRule.ownEventMarker
        let optionDown = event.flags.contains(.maskAlternate)
        let now = ProcessInfo.processInfo.systemUptime

        let verdict = state.withLock { state -> EdgeVerdict in
            let verdict = EdgeRule.verdict(at: location, optionDown: optionDown, isOwnEvent: isOwnEvent,
                                           snapshot: state.snapshot)
            if !isOwnEvent { state.status.lastUserPointerEvent = now }
            switch verdict {
            case .drop:
                state.status.droppedEvents += 1
                if !state.droppingVisit { state.status.blockedVisits += 1 }
                state.droppingVisit = true
            case .passOption:
                state.status.lastOptionPass = (now, location)
                state.droppingVisit = false
            case .pass, .passOwn:
                state.droppingVisit = false
            }
            return verdict
        }
        return verdict == .drop ? nil : Unmanaged.passUnretained(event)
    }
}
