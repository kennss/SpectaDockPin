//
//  @file        main.swift
//  @description DockProbe entry point: parses the command and runs it. DockProbe re-runs the Dock
//               experiments of Docs/DESIGN.md §3 and records the real-mouse checks of §8, so the table in
//               §3 can be re-checked whenever macOS changes.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//
//  Notes:
//  - `trigger` and `home` move the real cursor (and possibly the Dock). Tell whoever is at the Mac first.
//  - Run from a terminal that has the Accessibility permission (guard, trigger, home) and Input Monitoring
//    (watch). Never toggle the Accessibility permission while `guard` runs (DESIGN §12: input can freeze).
//

import AppKit
import Foundation

let usage = """
DockProbe — Dock behaviour experiments (Docs/DESIGN.md §3, §8). Coordinates are CG global points.

Read only:
  info  [--anchor <displayID>]         displays, Dock window, trigger rows, permissions, session
  where                                 which display the Dock is on

Record real input (nothing is posted):
  watch [--secs 180] [--rows 3] [--raw]
        listen-only tap; logs bottom-row visits and Dock moves
  guard [--secs 180] [--rows 3] [--raw] [--corner block|pass] [--no-option] [--anchor <displayID>]
        like watch, but drops pointer events on the trigger rows (Option held lets them through)

Move the real cursor (restored afterwards):
  trigger <x> <y> [--secs 4] [--dy 0] [--post hid|session|pid] [--kind moved|drag|once] [--guard]
        post events at one point and time how long until the Dock moves
  push  <x> <y> [--secs 4] [--step 3] [--dx 0] [--trace <n steps>]
        emulate a mouse pushed down from (x, y): each step starts at the current cursor, so warps count
  home  [--anchor <displayID>] [--style approach|point]
        call the Dock back to the anchor (default: main display), coming down from above by default
"""

_ = NSApplication.shared  // NSScreen.screensHaveSeparateSpaces is wrong without it (§3 S5)

let exitCode: Int32
do {
    var args = try Arguments(Array(CommandLine.arguments.dropFirst()))
    switch args.command {
    case "info": exitCode = try Commands.info(&args)
    case "where": exitCode = try Commands.whereIs(&args)
    case "watch": exitCode = try await Commands.session(&args, mode: .listen)
    case "guard": exitCode = try await Commands.session(&args, mode: .guardDrop)
    case "trigger": exitCode = try Commands.trigger(&args)
    case "push": exitCode = try Commands.push(&args)
    case "home": exitCode = try Commands.home(&args)
    case "help", "-h", "--help":
        print(usage)
        exitCode = 0
    default:
        throw UsageError(description: "unknown command \(args.command)")
    }
} catch let error as UsageError {
    print("error: \(error.description)\n\n\(usage)")
    exitCode = 64
}
exit(exitCode)
