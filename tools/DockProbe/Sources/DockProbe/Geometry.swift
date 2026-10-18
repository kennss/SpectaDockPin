//
//  @file        Geometry.swift
//  @description Display list and the edge geometry DockProbe guards and records: the 1-pt trigger rows
//               at the bottom of every non-anchor display, the bottom zones it records, and the point
//               used to call the Dock back to the anchor display. Pure value types plus one AppKit read.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//
//  Key declared values:
//  - All rects and points are CG global coordinates in points: origin at the top-left of the main
//    display, y grows downward. NSScreen (bottom-left origin) is used only for names and insets.
//  - The trigger row of a display is y ∈ [maxY − 1, maxY) (DESIGN §3 F2: only the last 1-pt row moves
//    the Dock). Stretches of that row with another display directly below are left out: they are a
//    passage to the next display, not a Dock trigger.
//  - Corner pixels are x < minX + 1 or x ≥ maxX − 1 on the trigger row (§3 F5: the Dock ignores them).
//

import AppKit
import CoreGraphics

/// One active display as CoreGraphics reports it.
struct DisplayInfo: Sendable, Equatable {
    let id: CGDirectDisplayID
    let uuid: String
    let name: String
    /// CG global bounds in points (top-left origin).
    let bounds: CGRect
    let isMain: Bool
    let isBuiltin: Bool
}

enum DisplayList {
    /// Active displays, main display first.
    @MainActor
    static func active() -> [DisplayInfo] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }

        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                names[number.uint32Value] = screen.localizedName
            }
        }

        let displays = ids.prefix(Int(count)).map { id -> DisplayInfo in
            let uuid = CGDisplayCreateUUIDFromDisplayID(id)
                .map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String } ?? "unknown"
            return DisplayInfo(
                id: id,
                uuid: uuid,
                name: names[id] ?? "Display \(id)",
                bounds: CGDisplayBounds(id),
                isMain: CGDisplayIsMain(id) != 0,
                isBuiltin: CGDisplayIsBuiltin(id) != 0
            )
        }
        return displays.sorted { $0.isMain && !$1.isMain }
    }
}

/// A half-open x interval [lower, upper).
struct XSpan: Sendable, Equatable {
    var lower: CGFloat
    var upper: CGFloat
    var length: CGFloat { upper - lower }
}

/// What the guard does with an event on a trigger row corner pixel.
enum CornerPolicy: String, Sendable {
    /// Drop corner pixels like the rest of the row.
    case block
    /// Let corner pixels through (for hot corners; §3 F5 says the Dock ignores them).
    case pass
}

/// The edge geometry for one display arrangement and one anchor display.
struct EdgeLayout: Sendable {
    struct Strip: Sendable {
        let displayIndex: Int
        /// 1-pt high rect on the display's last row.
        let rect: CGRect
    }

    let displays: [DisplayInfo]
    let anchorIndex: Int
    let strips: [Strip]
    /// Bottom-centre point of the anchor's longest free bottom stretch; nil when it has none.
    let relocationPoint: CGPoint?
    /// Number of bottom rows per display that the recorder logs (row 0 is the trigger row).
    let recordedRows: Int

    /// Builds the layout. Falls back to the main display when `anchorID` is nil or not connected.
    init(displays: [DisplayInfo], anchorID: CGDirectDisplayID?, recordedRows: Int) {
        self.displays = displays
        self.recordedRows = max(1, recordedRows)
        let anchorIndex = displays.firstIndex { $0.id == anchorID }
            ?? displays.firstIndex { $0.isMain }
            ?? 0
        self.anchorIndex = anchorIndex

        var strips: [Strip] = []
        for (index, display) in displays.enumerated() where index != anchorIndex {
            for span in Self.freeBottomSpans(of: index, in: displays) {
                strips.append(Strip(
                    displayIndex: index,
                    rect: CGRect(x: span.lower, y: display.bounds.maxY - 1, width: span.length, height: 1)
                ))
            }
        }
        self.strips = strips

        if displays.indices.contains(anchorIndex),
           let longest = Self.freeBottomSpans(of: anchorIndex, in: displays).max(by: { $0.length < $1.length }) {
            self.relocationPoint = CGPoint(
                x: (longest.lower + (longest.length / 2)).rounded(.down),
                y: displays[anchorIndex].bounds.maxY - 1
            )
        } else {
            self.relocationPoint = nil
        }
    }

    /// The parts of a display's bottom edge with no other display directly below.
    static func freeBottomSpans(of index: Int, in displays: [DisplayInfo]) -> [XSpan] {
        let bounds = displays[index].bounds
        var spans = [XSpan(lower: bounds.minX, upper: bounds.maxX)]
        for (otherIndex, other) in displays.enumerated() where otherIndex != index {
            guard abs(other.bounds.minY - bounds.maxY) < 0.5 else { continue }
            let cut = XSpan(lower: max(bounds.minX, other.bounds.minX), upper: min(bounds.maxX, other.bounds.maxX))
            guard cut.length > 0 else { continue }
            spans = spans.flatMap { span -> [XSpan] in
                var pieces: [XSpan] = []
                if cut.lower > span.lower { pieces.append(XSpan(lower: span.lower, upper: min(span.upper, cut.lower))) }
                if cut.upper < span.upper { pieces.append(XSpan(lower: max(span.lower, cut.upper), upper: span.upper)) }
                return pieces.filter { $0.length > 0 }
            }
        }
        return spans
    }

    /// The display under a point, or nil.
    func displayIndex(at point: CGPoint) -> Int? {
        displays.firstIndex { $0.bounds.contains(point) }
    }

    /// Bottom row of a point on a display: 0 is the last 1-pt row, 1 the row above, and so on.
    /// Nil when the point is above the recorded rows.
    func recordedRow(of point: CGPoint, displayIndex: Int) -> Int? {
        let distance = displays[displayIndex].bounds.maxY - point.y
        guard distance > 0 else { return nil }
        let row = Int(distance.rounded(.up)) - 1
        return row < recordedRows ? row : nil
    }
}

/// The guard's decision for one pointer event.
enum EdgeVerdict: Sendable {
    /// Not on a trigger row.
    case outside
    /// On a trigger row: dropped (or, in listen mode, would be dropped).
    case drop
    /// On a trigger row but Option was held (DESIGN §13 decision 3).
    case passOption
    /// On a trigger row corner pixel with `CornerPolicy.pass`.
    case passCorner
}

/// Pure guard rule, called from the tap thread for every pointer event.
struct EdgeRule: Sendable {
    let layout: EdgeLayout
    let cornerPolicy: CornerPolicy
    let optionBypass: Bool

    func verdict(at point: CGPoint, optionDown: Bool) -> EdgeVerdict {
        guard let strip = layout.strips.first(where: { $0.rect.contains(point) }) else { return .outside }
        let display = layout.displays[strip.displayIndex].bounds
        if cornerPolicy == .pass, point.x < display.minX + 1 || point.x >= display.maxX - 1 { return .passCorner }
        if optionBypass, optionDown { return .passOption }
        return .drop
    }
}
