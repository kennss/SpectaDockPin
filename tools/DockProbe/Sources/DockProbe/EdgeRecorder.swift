//
//  @file        EdgeRecorder.swift
//  @description Turns the tap's zone events into a readable log for the real-mouse checks (DESIGN §8
//               T1–T3): one summary line per visit to a display's bottom rows, one line per Dock move
//               with what the pointer was doing just before, and an end-of-run summary.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//
//  Notes:
//  - A "visit" starts with the first event on a display's recorded rows and ends with the first event
//    elsewhere. A pointer resting on the edge sends no events, so a visit can last longer than its events.
//  - Dock moves are matched to the current visit when the Dock moved to that visit's display. "r0 for X s"
//    is the time from the visit's first row-0 event to the moment the move was seen (poll ≤ 25 ms late).
//  - In listen mode "drop" counts are what guard mode would have dropped.
//
//  Key declared values:
//  - maxDistinctY: how many distinct y values a visit keeps for the summary (fractional rows, T3).
//

import CoreGraphics
import Foundation

@MainActor
final class EdgeRecorder {
    static let maxDistinctY = 6

    private struct Visit {
        let displayIndex: Int
        let start: TimeInterval
        var last: TimeInterval
        var firstRow0: TimeInterval?
        var lastRow0: TimeInterval?
        var rowCounts: [Int]
        var moved = 0
        var dragged = 0
        var deltaYMin = Int64.max
        var deltaYMax = Int64.min
        var distinctY: [CGFloat] = []
        var drops = 0
        var optionPasses = 0
        var cornerPasses = 0
        var synthetic = 0
        var dockArrived = false
    }

    private let layout: EdgeLayout
    private let mode: TapMode
    private let raw: Bool
    private let origin: TimeInterval
    private var visit: Visit?
    private var dock: DockPlacement?
    private var dockMoves = 0
    private var visits = 0

    init(layout: EdgeLayout, mode: TapMode, raw: Bool, origin: TimeInterval) {
        self.layout = layout
        self.mode = mode
        self.raw = raw
        self.origin = origin
    }

    func ingest(_ events: [ZoneEvent]) {
        for event in events {
            if raw { printRaw(event) }
            guard event.displayIndex >= 0 else {
                closeVisit(at: event.time)
                continue
            }
            if visit?.displayIndex != event.displayIndex {
                closeVisit(at: event.time)
                visit = Visit(
                    displayIndex: event.displayIndex, start: event.time, last: event.time,
                    rowCounts: Array(repeating: 0, count: layout.recordedRows)
                )
            }
            guard var current = visit else { continue }
            current.last = event.time
            current.rowCounts[event.row] += 1
            if event.row == 0 {
                if current.firstRow0 == nil { current.firstRow0 = event.time }
                current.lastRow0 = event.time
            }
            if event.type == .mouseMoved { current.moved += 1 } else { current.dragged += 1 }
            current.deltaYMin = min(current.deltaYMin, event.deltaY)
            current.deltaYMax = max(current.deltaYMax, event.deltaY)
            if current.distinctY.count < Self.maxDistinctY, !current.distinctY.contains(event.location.y) {
                current.distinctY.append(event.location.y)
            }
            switch event.verdict {
            case .drop: current.drops += 1
            case .passOption: current.optionPasses += 1
            case .passCorner: current.cornerPasses += 1
            case .outside: break
            }
            if event.synthetic { current.synthetic += 1 }
            visit = current
        }
    }

    /// Call after each drain with the Dock's current placement.
    func observeDock(_ placement: DockPlacement, at time: TimeInterval) {
        defer { dock = placement }
        guard let previous = dock else {
            log(time, "Dock is on \(name(of: placement))")
            return
        }
        guard previous != placement else { return }
        dockMoves += 1
        var line = "DOCK MOVED \(name(of: previous)) → \(name(of: placement))"
        if case .display(let index) = placement, let current = visit, current.displayIndex == index {
            visit?.dockArrived = true
            if let firstRow0 = current.firstRow0, let lastRow0 = current.lastRow0 {
                line += String(
                    format: " — pointer on its r0 for %.2f s (%d r0 events, last %.2f s before)",
                    time - firstRow0, current.rowCounts[0], time - lastRow0
                )
            } else {
                line += " — pointer on its bottom rows but never on r0"
            }
        } else {
            line += " — pointer not on that display's bottom rows"
        }
        log(time, line)
    }

    func finish(at time: TimeInterval, counters: TapCounters) {
        closeVisit(at: time)
        log(time, "END visits \(visits), Dock moves \(dockMoves); events seen \(counters.seen), on trigger rows \(counters.triggerRowHits), dropped \(counters.dropped); tap disabled by timeout \(counters.disabledByTimeout), by user input \(counters.disabledByUserInput)")
    }

    private func closeVisit(at time: TimeInterval) {
        guard let current = visit else { return }
        visit = nil
        visits += 1
        let display = layout.displays[current.displayIndex].name
        let rows = current.rowCounts.enumerated().map { "r\($0.offset) \($0.element)" }.joined(separator: " · ")
        let ys = current.distinctY.map { String(format: "%.1f", $0) }.joined(separator: ",")
        var line = String(format: "%@ bottom %.2f s  %@  moved %d drag %d  dy %lld…%lld  y{%@}",
                          display, time - current.start, rows, current.moved, current.dragged,
                          current.deltaYMin, current.deltaYMax, ys)
        let dropWord = mode == .guardDrop ? "dropped" : "would-drop"
        if current.drops > 0 { line += "  \(dropWord) \(current.drops)" }
        if current.optionPasses > 0 { line += "  option-pass \(current.optionPasses)" }
        if current.cornerPasses > 0 { line += "  corner-pass \(current.cornerPasses)" }
        if current.synthetic > 0 { line += "  synthetic \(current.synthetic)" }
        if current.dockArrived { line += "  [Dock came here]" }
        log(current.start, line)
    }

    private func printRaw(_ event: ZoneEvent) {
        guard event.displayIndex >= 0 else {
            log(event.time, String(format: "  left bottom rows at (%.1f,%.1f)", event.location.x, event.location.y))
            return
        }
        let kind = event.type == .mouseMoved ? "moved" : "drag"
        let verdict: String
        switch event.verdict {
        case .drop: verdict = mode == .guardDrop ? "drop" : "would-drop"
        case .passOption: verdict = "pass-option"
        case .passCorner: verdict = "pass-corner"
        case .outside: verdict = ""
        }
        log(event.time, String(format: "  %@ r%d %@ (%.1f,%.1f) dy %lld %@%@",
                               layout.displays[event.displayIndex].name, event.row, kind,
                               event.location.x, event.location.y, event.deltaY, verdict,
                               event.synthetic ? " synthetic" : ""))
    }

    private func name(of placement: DockPlacement) -> String {
        switch placement {
        case .display(let index): layout.displays[index].name
        case .unknown: "unknown"
        }
    }

    private func log(_ time: TimeInterval, _ text: String) {
        print(String(format: "+%7.3f  ", time - origin) + text)
        fflush(stdout)
    }
}
