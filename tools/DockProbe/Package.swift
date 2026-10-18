// swift-tools-version: 6.0
//
//  @file        Package.swift
//  @description SwiftPM manifest for DockProbe, the command-line tool that re-runs the Dock experiments
//               of Docs/DESIGN.md §3 (and records the real-mouse checks T1–T3 of §8).
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//
//  Notes:
//  - Kept outside project.yml on purpose: the probe checks what macOS does, independent of the app's
//    own code, so a bug in the app's DisplayMap or DockLocator cannot hide a change in macOS behaviour.
//  - Build with the Xcode toolchain (`xcrun swift build`); a swiftly toolchain on PATH may lack the
//    macOS SDK modules (CoreGraphics, AppKit).
//

import PackageDescription

let package = Package(
    name: "DockProbe",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DockProbe",
            path: "Sources/DockProbe",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
