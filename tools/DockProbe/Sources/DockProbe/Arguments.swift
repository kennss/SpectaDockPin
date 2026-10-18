//
//  @file        Arguments.swift
//  @description Minimal command-line parsing for DockProbe: positional values plus `--name value` and
//               `--flag` options. No package dependency, so the tool builds offline.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//

import Foundation

struct UsageError: Error, CustomStringConvertible {
    let description: String
}

struct Arguments {
    let command: String
    private(set) var positional: [String] = []
    private var options: [String: String] = [:]
    private var flags: Set<String> = []
    private var consumed: Set<String> = []

    /// Options that never take a value.
    static let flagNames: Set<String> = ["guard", "raw", "no-option", "help"]

    init(_ arguments: [String]) throws {
        command = arguments.first ?? "help"
        var index = 1
        while index < arguments.count {
            let item = arguments[index]
            if item.hasPrefix("--") {
                let name = String(item.dropFirst(2))
                if Self.flagNames.contains(name) {
                    flags.insert(name)
                } else {
                    guard index + 1 < arguments.count else { throw UsageError(description: "--\(name) needs a value") }
                    options[name] = arguments[index + 1]
                    index += 1
                }
            } else {
                positional.append(item)
            }
            index += 1
        }
    }

    mutating func flag(_ name: String) -> Bool {
        consumed.insert(name)
        return flags.contains(name)
    }

    mutating func double(_ name: String, default value: Double) throws -> Double {
        consumed.insert(name)
        guard let text = options[name] else { return value }
        guard let number = Double(text) else { throw UsageError(description: "--\(name) expects a number, got \(text)") }
        return number
    }

    mutating func int(_ name: String, default value: Int) throws -> Int {
        consumed.insert(name)
        guard let text = options[name] else { return value }
        guard let number = Int(text) else { throw UsageError(description: "--\(name) expects an integer, got \(text)") }
        return number
    }

    mutating func string(_ name: String, default value: String) -> String {
        consumed.insert(name)
        return options[name] ?? value
    }

    mutating func optionalUInt32(_ name: String) throws -> UInt32? {
        consumed.insert(name)
        guard let text = options[name] else { return nil }
        guard let number = UInt32(text) else { throw UsageError(description: "--\(name) expects a display ID, got \(text)") }
        return number
    }

    /// Fails on options the command did not ask for, so a typo cannot silently change an experiment.
    func rejectUnknown() throws {
        let unknown = Set(options.keys).union(flags).subtracting(consumed)
        if let first = unknown.sorted().first { throw UsageError(description: "unknown option --\(first) for \(command)") }
    }
}
