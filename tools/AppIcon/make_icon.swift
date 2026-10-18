//
//  @file        make_icon.swift
//  @description Draws the SpectaDockPin app icon with CoreGraphics and writes every macOS size into
//               SpectaDockPin/Resources/Assets.xcassets/AppIcon.appiconset (plus Contents.json). The icon is
//               the source of truth here, not a PNG: re-run after changing it.
//               Run from the repo root: xcrun swift tools/AppIcon/make_icon.swift
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//
//  Notes:
//  - Specta family DNA (SpectArk design handoff): light glass squircle body, blue main shape, amber accent.
//    Here: a blue display whose white Dock bar is held down by an amber pin.
//  - Every size is drawn as vectors at its own pixel size (no downscaling), so 16 and 32 px stay crisp.
//  - Geometry is in a 1024 × 1024 design space with y growing DOWN; `s` scales it to the output size.
//    Shadow offsets are in device space (CoreGraphics ignores the CTM for them), so they use negative y.
//
//  Key declared values:
//  - Body: Apple's macOS icon grid, an 824-pt superellipse (exponent 4 — 5 looked boxier than the family) inset 100 pt, drop shadow below
//    (matches SpectArk's mac icon: body 95–929, shadow fading out by ~1000).
//  - Colours: glass #EAF1FB → #D2E0F2 → #BCD0EA; blue #5AB6FF → #1A7BF0 → #0A3A8C; amber #FFE873 → #F5C400
//    (the Specta amber, #F5C400).
//

import AppKit
import CoreGraphics

/// Scale of the glyph inside the body, around (512, 500).
let glyphScale: CGFloat = 1.1

// MARK: - Helpers

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
               colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
}

/// A superellipse ("squircle") filling `rect`.
func squircle(_ rect: CGRect, exponent n: CGFloat = 4) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), sn = sin(t)
        let x = rect.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = rect.midY + b * (sn < 0 ? -1 : 1) * pow(abs(sn), 2 / n)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// A map-pin teardrop: a circle whose sides run tangent down to a point.
func teardrop(center: CGPoint, radius r: CGFloat, tip: CGPoint) -> CGPath {
    let d = tip.y - center.y
    let phi = acos(r / d)                      // angle between the downward axis and a tangent point
    let path = CGMutablePath()
    path.move(to: tip)
    // Right tangent point, then around the top to the left tangent point (y-down space).
    let steps = 240
    let start = CGFloat.pi / 2 - phi           // measured from +x, y down: pi/2 points straight down
    let end = CGFloat.pi / 2 + phi - 2 * .pi
    for i in 0...steps {
        let t = start + (end - start) * CGFloat(i) / CGFloat(steps)
        path.addLine(to: CGPoint(x: center.x + r * cos(t), y: center.y + r * sin(t)))
    }
    path.closeSubpath()
    return path
}

extension CGContext {
    func fill(_ path: CGPath, _ gradient: CGGradient, from top: CGFloat, to bottom: CGFloat) {
        saveGState()
        addPath(path)
        clip()
        drawLinearGradient(gradient, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom), options: [])
        restoreGState()
    }

    func shadowed(offsetY: CGFloat, blur: CGFloat, color: CGColor, _ draw: () -> Void) {
        saveGState()
        setShadow(offset: CGSize(width: 0, height: -offsetY), blur: blur, color: color)
        beginTransparencyLayer(auxiliaryInfo: nil)
        draw()
        endTransparencyLayer()
        restoreGState()
    }
}

// MARK: - Drawing

func drawIcon(size: Int) -> CGImage {
    let px = CGFloat(size)
    let s = px / 1024
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: px)
    ctx.scaleBy(x: s, y: -s)                   // 1024 design space, y down
    ctx.setShouldAntialias(true)

    // Body: glass squircle with a soft drop shadow.
    let bodyRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let body = squircle(bodyRect)
    ctx.shadowed(offsetY: 12 * s, blur: 28 * s, color: rgb(0x0A2A5C, 0.32)) {
        ctx.addPath(body)
        ctx.setFillColor(rgb(0xD2E0F2))
        ctx.fillPath()
    }
    ctx.fill(body, gradient([(0, rgb(0xEAF1FB)), (0.55, rgb(0xD2E0F2)), (1, rgb(0xBCD0EA))]), from: 100, to: 924)
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    ctx.drawLinearGradient(gradient([(0, rgb(0xFFFFFF, 0.55)), (1, rgb(0xFFFFFF, 0))]),
                           start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 560), options: [])
    ctx.drawRadialGradient(gradient([(0, rgb(0xFFFFFF, 0.45)), (1, rgb(0xFFFFFF, 0))]),
                           startCenter: CGPoint(x: 360, y: 240), startRadius: 0,
                           endCenter: CGPoint(x: 360, y: 240), endRadius: 300, options: [])
    ctx.drawLinearGradient(gradient([(0, rgb(0x0050B4, 0)), (1, rgb(0x0050B4, 0.14))]),
                           start: CGPoint(x: 0, y: 640), end: CGPoint(x: 0, y: 924), options: [])
    ctx.restoreGState()
    ctx.addPath(squircle(bodyRect.insetBy(dx: 2, dy: 2)))
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.75))
    ctx.setLineWidth(4)
    ctx.strokePath()

    let depth = rgb(0x0A3A8C, 0.38)

    // The glyph (stand, display, Dock bar, pin) is drawn 10% larger around its centre so it carries the same
    // weight as its siblings' glyphs (compared side by side in Finder, 2026-10-18).
    ctx.translateBy(x: 512, y: 500)
    ctx.scaleBy(x: glyphScale, y: glyphScale)
    ctx.translateBy(x: -512, y: -500)

    // Stand: neck and base, behind the display.
    let neck = CGMutablePath()
    neck.move(to: CGPoint(x: 470, y: 620))
    neck.addLine(to: CGPoint(x: 554, y: 620))
    neck.addLine(to: CGPoint(x: 572, y: 714))
    neck.addLine(to: CGPoint(x: 452, y: 714))
    neck.closeSubpath()
    let base = roundedRect(CGRect(x: 372, y: 704, width: 280, height: 34), 17)
    ctx.shadowed(offsetY: 8 * s, blur: 18 * s, color: depth) {
        ctx.fill(neck, gradient([(0, rgb(0x3D8BEA)), (1, rgb(0x1A5FC8))]), from: 620, to: 714)
        ctx.fill(base, gradient([(0, rgb(0x5AA8FA)), (1, rgb(0x1A5FC8))]), from: 704, to: 738)
    }

    // Display.
    let screenRect = CGRect(x: 224, y: 262, width: 576, height: 372)
    let screen = roundedRect(screenRect, 46)
    ctx.shadowed(offsetY: 10 * s, blur: 24 * s, color: depth) {
        ctx.fill(screen, gradient([(0, rgb(0x5AB6FF)), (0.55, rgb(0x1A7BF0)), (1, rgb(0x0A3A8C))]),
                 from: screenRect.minY, to: screenRect.maxY)
    }
    let sheen = CGMutablePath()
    sheen.move(to: CGPoint(x: 270, y: 282))
    sheen.addLine(to: CGPoint(x: 754, y: 282))
    sheen.addQuadCurve(to: CGPoint(x: 780, y: 308), control: CGPoint(x: 780, y: 282))
    sheen.addLine(to: CGPoint(x: 780, y: 360))
    sheen.addQuadCurve(to: CGPoint(x: 244, y: 360), control: CGPoint(x: 512, y: 322))
    sheen.addLine(to: CGPoint(x: 244, y: 308))
    sheen.addQuadCurve(to: CGPoint(x: 270, y: 282), control: CGPoint(x: 244, y: 282))
    sheen.closeSubpath()
    ctx.fill(sheen, gradient([(0, rgb(0xFFFFFF, 0.55)), (1, rgb(0xFFFFFF, 0))]), from: 282, to: 360)
    ctx.addPath(screen)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.5))
    ctx.setLineWidth(5)
    ctx.strokePath()

    // Dock bar along the bottom of the display, with app tiles either side of the pin.
    let barRect = CGRect(x: 332, y: 552, width: 360, height: 52)
    let bar = roundedRect(barRect, 26)
    ctx.shadowed(offsetY: 6 * s, blur: 12 * s, color: rgb(0x0A3A8C, 0.45)) {
        ctx.fill(bar, gradient([(0, rgb(0xFFFFFF)), (1, rgb(0xE3EFFF))]), from: barRect.minY, to: barRect.maxY)
    }
    for x in [366.0, 418.0, 574.0, 626.0] {
        let tile = roundedRect(CGRect(x: x, y: 564, width: 32, height: 28), 8)
        ctx.fill(tile, gradient([(0, rgb(0x8CC6FF)), (1, rgb(0x3D8BEA))]), from: 564, to: 592)
    }

    // Amber pin pressing into the middle of the bar.
    let pinCenter = CGPoint(x: 512, y: 424)
    let pin = teardrop(center: pinCenter, radius: 78, tip: CGPoint(x: 512, y: 586))
    ctx.shadowed(offsetY: 10 * s, blur: 20 * s, color: rgb(0x7A4A00, 0.40)) {
        ctx.fill(pin, gradient([(0, rgb(0xFFE873)), (1, rgb(0xF5C400))]), from: 346, to: 586)
    }
    ctx.saveGState()
    ctx.addPath(pin)
    ctx.clip()
    ctx.drawRadialGradient(gradient([(0, rgb(0xFFFFFF, 0.55)), (1, rgb(0xFFFFFF, 0))]),
                           startCenter: CGPoint(x: 482, y: 384), startRadius: 0,
                           endCenter: CGPoint(x: 482, y: 384), endRadius: 70, options: [])
    ctx.restoreGState()
    ctx.addPath(pin)
    ctx.setStrokeColor(rgb(0xD99A00, 0.55))
    ctx.setLineWidth(3)
    ctx.strokePath()
    ctx.addEllipse(in: CGRect(x: pinCenter.x - 30, y: pinCenter.y - 30, width: 60, height: 60))
    ctx.setFillColor(rgb(0xFFFFFF, 0.96))
    ctx.fillPath()

    return ctx.makeImage()!
}

// MARK: - Output

let out = URL(fileURLWithPath: "SpectaDockPin/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let rep = NSBitmapImageRep(cgImage: drawIcon(size: size))
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: out.appendingPathComponent("mac-\(size).png"))
}
let entries: [(String, String, Int)] = [
    ("16x16", "1x", 16), ("16x16", "2x", 32), ("32x32", "1x", 32), ("32x32", "2x", 64),
    ("128x128", "1x", 128), ("128x128", "2x", 256), ("256x256", "1x", 256), ("256x256", "2x", 512),
    ("512x512", "1x", 512), ("512x512", "2x", 1024),
]
let images = entries.map { size, scale, file in
    "    { \"filename\" : \"mac-\(file).png\", \"idiom\" : \"mac\", \"scale\" : \"\(scale)\", \"size\" : \"\(size)\" }"
}
let json = "{\n  \"images\" : [\n\(images.joined(separator: ",\n"))\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
try json.write(to: out.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("wrote \(out.path)")
