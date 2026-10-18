//
//  @file        DisplayWatcher.swift
//  @description Reads the active displays and reports arrangement changes (connect, disconnect, resolution,
//               arrangement, main display) after they settle (DESIGN §5.1).
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//
//  Notes:
//  - NSApplication.didChangeScreenParametersNotification covers every change the map depends on and arrives
//    on the main thread; changes come in bursts, so the callback runs once, displayDebounce after the last.
//  - Names come from NSScreen.localizedName, matched by display ID.
//

import AppKit
import CoreGraphics

@MainActor
final class DisplayWatcher {
    private var observer: NSObjectProtocol?
    private var debounce: Task<Void, Never>?

    /// Called on the main actor, once per settled change.
    var onChange: (() -> Void)?

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleChange() }
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        debounce?.cancel()
        debounce = nil
    }

    private func scheduleChange() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: PinTuning.displayDebounce)
            guard !Task.isCancelled else { return }
            self?.onChange?()
        }
    }

    /// The active displays now, main display first.
    static func activeDisplays() -> [DisplayInfo] {
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
        return ids.prefix(Int(count))
            .map { id in
                DisplayInfo(
                    id: id,
                    uuid: CGDisplayCreateUUIDFromDisplayID(id)
                        .map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String } ?? "display-\(id)",
                    name: names[id] ?? String(localized: "Display \(id)"),
                    bounds: CGDisplayBounds(id),
                    isMain: CGDisplayIsMain(id) != 0
                )
            }
            .sorted { $0.isMain && !$1.isMain }
    }
}
