//
//  @file        PermissionView.swift
//  @description The first-run window that explains the one permission SpectaDockPin needs and opens the
//               setting (DESIGN §5.7), plus the AppKit window that hosts it.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//
//  Notes:
//  - The setting is described, not named: macOS 27 calls the pane "Device Control and Data Access" and
//    earlier versions "Accessibility" (S8).
//  - It warns to quit the app before turning the permission off: a dropping tap without its grant has been
//    reported to freeze all input until restart (§12).
//  - An AppKit window rather than a SwiftUI scene: a menu-bar-only app has no view alive at launch to call
//    openWindow from. LSUIElement apps must activate to bring the window forward.
//  - Shows the app icon (tools/AppIcon); text stays in the system colours (DESIGN §7 brand).
//

import AppKit
import SwiftUI

struct PermissionView: View {
    @Environment(AppModel.self) private var model
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("SpectaDockPin").font(.title2.weight(.semibold))
                    Text("Keeps the Dock on one display.").foregroundStyle(.secondary)
                }
            }

            Text("To stop the Dock from jumping, SpectaDockPin needs the privacy setting that lets it control the pointer. It only ignores pointer moves on the bottom edge of your other displays, and moves the pointer only to bring the Dock back. It never reads the keyboard and sends nothing over the network.")
                .fixedSize(horizontal: false, vertical: true)

            Text("Turn SpectaDockPin on in System Settings, in the list of apps allowed to control your computer. If it isn't listed, add it with the + button from the Applications folder.")
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)

            Label("Quit SpectaDockPin before you turn this permission off.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)

            HStack {
                if model.hasPermission {
                    Label("Permission granted — the Dock is guarded.", systemImage: "checkmark.circle.fill")
                    Spacer()
                    Button("Done", action: close).keyboardShortcut(.defaultAction)
                } else {
                    Label("Waiting for permission…", systemImage: "hourglass")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open System Settings") { model.requestPermission() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

/// Hosts PermissionView in a plain window; one instance, reused.
@MainActor
final class OnboardingWindow {
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = String(localized: "SpectaDockPin")
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(
                rootView: PermissionView(close: { [weak window] in window?.close() }).environment(model)
            )
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
