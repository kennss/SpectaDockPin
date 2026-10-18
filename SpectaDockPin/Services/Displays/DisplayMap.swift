//
//  @file        DisplayMap.swift
//  @description Pure geometry for one display arrangement: which display is the anchor, which 1-pt rows to
//               guard, and where to call the Dock back to (DESIGN §5.1). No system calls — unit-tested.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//
//  Key declared values:
//  - All rects and points are CG global coordinates in points: origin at the top-left of the main display,
//    y grows downward. NSScreen coordinates (bottom-left origin) never enter here (dock-cleat's bug, §2).
//  - A trigger row is y ∈ [maxY − 1, maxY) of a display (F2). Stretches of it with another display directly
//    below are left out: there the pointer passes to the next display instead of calling the Dock.
//  - Corner pixels are part of the row: they move the Dock too (F23, DESIGN §13 decision 8).
//  - relocationPoint is the middle of the anchor's longest free bottom stretch, on its last row.
//

import CoreGraphics

/// One active display.
struct DisplayInfo: Sendable, Equatable, Identifiable {
    let id: CGDirectDisplayID
    /// CGDisplayCreateUUIDFromDisplayID; stable across reconnects, unlike `id`.
    let uuid: String
    let name: String
    /// CG global bounds in points.
    let bounds: CGRect
    let isMain: Bool
}

/// A half-open x interval [lower, upper).
struct XSpan: Sendable, Equatable {
    var lower: CGFloat
    var upper: CGFloat
    var length: CGFloat { upper - lower }
}

struct DisplayMap: Sendable, Equatable {
    let displays: [DisplayInfo]
    /// The display the Dock is pinned to; nil only when no display is connected.
    let anchor: DisplayInfo?
    /// A display was chosen but is not connected, so the main display stands in (DESIGN §6).
    let anchorIsFallback: Bool

    init(displays: [DisplayInfo], preferredAnchorUUID: String?) {
        self.displays = displays
        let preferred = preferredAnchorUUID.flatMap { uuid in displays.first { $0.uuid == uuid } }
        anchor = preferred ?? displays.first { $0.isMain } ?? displays.first
        anchorIsFallback = preferredAnchorUUID != nil && preferred == nil
    }

    static let empty = DisplayMap(displays: [], preferredAnchorUUID: nil)

    func display(id: CGDirectDisplayID) -> DisplayInfo? {
        displays.first { $0.id == id }
    }

    func display(containing point: CGPoint) -> DisplayInfo? {
        displays.first { $0.bounds.contains(point) }
    }

    /// The rows to guard: the free bottom stretches of every display except the anchor and `alsoExcluded`
    /// (the display the Dock is on when the user moved it there, whose row must stay usable — §5.2).
    func triggerStrips(alsoExcluding alsoExcluded: CGDirectDisplayID? = nil) -> [CGRect] {
        displays.flatMap { display -> [CGRect] in
            guard display.id != anchor?.id, display.id != alsoExcluded else { return [] }
            return Self.freeBottomSpans(of: display, in: displays).map { span in
                CGRect(x: span.lower, y: display.bounds.maxY - PinTuning.triggerRowHeight,
                       width: span.length, height: PinTuning.triggerRowHeight)
            }
        }
    }

    /// Where the Relocator brings the pointer down onto the anchor's last row; nil when it has no free edge.
    var relocationPoint: CGPoint? {
        guard let anchor,
              let longest = Self.freeBottomSpans(of: anchor, in: displays).max(by: { $0.length < $1.length })
        else { return nil }
        return CGPoint(x: (longest.lower + longest.length / 2).rounded(.down),
                       y: anchor.bounds.maxY - PinTuning.triggerRowHeight)
    }

    /// The parts of a display's bottom edge with no other display directly below.
    static func freeBottomSpans(of display: DisplayInfo, in displays: [DisplayInfo]) -> [XSpan] {
        let bounds = display.bounds
        var spans = [XSpan(lower: bounds.minX, upper: bounds.maxX)]
        for other in displays where other.id != display.id {
            guard abs(other.bounds.minY - bounds.maxY) < PinTuning.adjacencyTolerance else { continue }
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
}
