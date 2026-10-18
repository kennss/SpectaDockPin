//
//  @file        EdgeTap.swift
//  @description The event tap DockProbe runs on its own thread, in one of two modes: listen (records
//               pointer events on the bottom rows, changes nothing) or guard (also drops the events that
//               land on a trigger row, as the app's EdgeGuard will — DESIGN §5.2).
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//
//  Notes:
//  - Tap: .cgSessionEventTap + .headInsertEventTap (§3 F4). Guard mode uses .defaultTap (needs the
//    Accessibility permission), listen mode .listenOnly (needs Input Monitoring) and can never block input.
//  - The tap is created, run and torn down on its own thread's run loop, so a busy main thread cannot get
//    it disabled by timeout (I5). The callback only runs EdgeRule and appends to a lock-protected buffer.
//  - CF objects (CFMachPort, CFRunLoop, CFRunLoopSource) are not Sendable. They live in `handles`, an
//    OSAllocatedUnfairLock created with uncheckedState: they are only touched under that lock, and the calls
//    made on them from other threads (tapEnable, CFRunLoopRemoveSource, CFMachPortInvalidate, CFRunLoopStop)
//    are thread-safe.
//  - stop() disables the tap, removes its source, invalidates the port, then stops the thread, in that order
//    (I4: the tap goes first). Call it before anything else when the Accessibility grant goes away.
//
//  Key declared values:
//  - ProbeMarker.value: eventSourceUserData stamped on every event DockProbe posts itself ("SPPR"), unlike
//    the app's "SPDP", so a running SpectaDockPin drops probe events as it would real ones.
//  - maxPendingEvents: cap on the buffer between drains, so an undrained tap cannot grow without bound.
//

import CoreGraphics
import Foundation
import os

enum TapMode: Sendable {
    case listen
    case guardDrop
}

/// Marks events DockProbe posts itself, so logs can tell them from real input. Deliberately different from
/// the app's EdgeRule.ownEventMarker ("SPDP"): the app must treat probe events like a user's and drop them.
enum ProbeMarker {
    static let value: Int64 = 0x5350_5052   // "SPPR"
}

/// One pointer event on a display's recorded bottom rows (or the first event after leaving them).
struct ZoneEvent: Sendable {
    /// Seconds since boot (ProcessInfo.systemUptime).
    let time: TimeInterval
    let type: CGEventType
    let location: CGPoint
    let deltaY: Int64
    /// Index into EdgeLayout.displays; -1 marks "left the recorded rows".
    let displayIndex: Int
    /// 0 = last 1-pt row.
    let row: Int
    let verdict: EdgeVerdict
    let synthetic: Bool
    let optionDown: Bool
}

struct TapCounters: Sendable {
    var seen = 0
    /// Events whose verdict was .drop, whether or not this mode drops them.
    var triggerRowHits = 0
    var dropped = 0
    var disabledByTimeout = 0
    var disabledByUserInput = 0
}

private struct TapState: Sendable {
    var pending: [ZoneEvent] = []
    var counters = TapCounters()
    var wasInZone = false
}

private struct TapHandles {
    var port: CFMachPort?
    var source: CFRunLoopSource?
    var runLoop: CFRunLoop?
}

final class EdgeTap: Sendable {
    static let maxPendingEvents = 100_000
    static let eventMask: CGEventMask = [
        CGEventType.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
    ].reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }

    let mode: TapMode
    let rule: EdgeRule
    private let state = OSAllocatedUnfairLock(initialState: TapState())
    private let handles = OSAllocatedUnfairLock<TapHandles>(uncheckedState: TapHandles())
    private let finished = DispatchSemaphore(value: 0)

    init(mode: TapMode, rule: EdgeRule) {
        self.mode = mode
        self.rule = rule
    }

    /// Starts the tap thread. False when the tap could not be created (missing permission).
    func start() -> Bool {
        let ready = DispatchSemaphore(value: 0)
        let created = OSAllocatedUnfairLock(initialState: false)
        let thread = Thread { [self] in
            let options: CGEventTapOptions = mode == .guardDrop ? .defaultTap : .listenOnly
            guard let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: options,
                eventsOfInterest: Self.eventMask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    return Unmanaged<EdgeTap>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                ready.signal()
                finished.signal()
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
            finished.signal()
        }
        thread.name = "DockProbe.EdgeTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        return created.withLock { $0 }
    }

    /// Disables and removes the tap, then ends its thread. Safe to call more than once.
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
        if wasRunning { _ = finished.wait(timeout: .now() + 1) }
    }

    /// Safety net on top of the callback's own re-enable. True when the tap had to be switched back on.
    func reenableIfDisabled() -> Bool {
        handles.withLockUnchecked { handles in
            guard let port = handles.port, !CGEvent.tapIsEnabled(tap: port) else { return false }
            CGEvent.tapEnable(tap: port, enable: true)
            return true
        }
    }

    /// Takes the buffered zone events and the current counters.
    func drain() -> ([ZoneEvent], TapCounters) {
        state.withLock { state in
            let events = state.pending
            state.pending.removeAll(keepingCapacity: true)
            return (events, state.counters)
        }
    }

    /// Tap thread only.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // stop() disabling the tap also lands here as .tapDisabledByUserInput (seen 2026-10-18). By the
            // time this lock is ours, stop() has cleared the port, so a tap being torn down is neither
            // re-enabled nor counted.
            let reenabled = handles.withLockUnchecked { handles -> Bool in
                guard let port = handles.port else { return false }
                CGEvent.tapEnable(tap: port, enable: true)
                return true
            }
            if reenabled {
                state.withLock { state in
                    if type == .tapDisabledByTimeout {
                        state.counters.disabledByTimeout += 1
                    } else {
                        state.counters.disabledByUserInput += 1
                    }
                }
            }
            return Unmanaged.passUnretained(event)
        }

        let location = event.location
        let optionDown = event.flags.contains(.maskAlternate)
        let verdict = rule.verdict(at: location, optionDown: optionDown)
        let drop = mode == .guardDrop && verdict == .drop

        let layout = rule.layout
        let zone: (display: Int, row: Int)? = layout.displayIndex(at: location).flatMap { display in
            layout.recordedRow(of: location, displayIndex: display).map { (display, $0) }
        }
        let time = ProcessInfo.processInfo.systemUptime
        let synthetic = event.getIntegerValueField(.eventSourceUserData) == ProbeMarker.value
        let deltaY = event.getIntegerValueField(.mouseEventDeltaY)

        state.withLock { state in
            state.counters.seen += 1
            if verdict == .drop { state.counters.triggerRowHits += 1 }
            if drop { state.counters.dropped += 1 }
            guard state.pending.count < Self.maxPendingEvents else { return }
            if let zone {
                state.wasInZone = true
                state.pending.append(ZoneEvent(
                    time: time, type: type, location: location, deltaY: deltaY,
                    displayIndex: zone.display, row: zone.row, verdict: verdict,
                    synthetic: synthetic, optionDown: optionDown
                ))
            } else if state.wasInZone {
                state.wasInZone = false
                state.pending.append(ZoneEvent(
                    time: time, type: type, location: location, deltaY: deltaY,
                    displayIndex: -1, row: -1, verdict: verdict,
                    synthetic: synthetic, optionDown: optionDown
                ))
            }
        }
        return drop ? nil : Unmanaged.passUnretained(event)
    }
}
