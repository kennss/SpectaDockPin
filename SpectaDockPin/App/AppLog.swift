//
//  @file        AppLog.swift
//  @description Loggers, one per area. Coordinates and states only — never window titles or app names
//               (DESIGN §7, I8).
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//
//  Notes:
//  - Read with: log stream --predicate 'subsystem == "ai.calidalab.spectadockpin"'
//

import os

enum AppLog {
    private static let subsystem = "ai.calidalab.spectadockpin"

    static let guardTap = Logger(subsystem: subsystem, category: "Guard")
    static let dock = Logger(subsystem: subsystem, category: "Dock")
    static let relocate = Logger(subsystem: subsystem, category: "Relocate")
    static let session = Logger(subsystem: subsystem, category: "Session")
    static let permission = Logger(subsystem: subsystem, category: "Permission")
}
