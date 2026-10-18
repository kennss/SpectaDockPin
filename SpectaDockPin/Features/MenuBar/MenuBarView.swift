//
//  @file        MenuBarView.swift
//  @description The menu-bar menu (DESIGN §6): status, Move Dock Back Now, Pin To, Pause, Launch at Login,
//               the permission entry when needed, the Option hint, updates (Sparkle), Quit.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-19
//
//  Notes:
//  - MenuBarExtra .menu style: Text rows are disabled menu items, a Picker becomes a submenu with check marks,
//    a Toggle a checkable item.
//  - Pin To stores the display's UUID; "Main Display" stores nil and follows whichever display is main. A
//    chosen display that is not connected is listed as such and the main display stands in (DESIGN §6).
//  - Quit removes the tap before the app ends (§12).
//

import SwiftUI

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(UpdaterController.self) private var updater

    var body: some View {
        Text(model.status.headline)
        if model.blockedToday > 0 {
            Text("Stopped \(model.blockedToday) Dock jumps today")
        }
        if let last = model.lastRelocation {
            Text(last.succeeded
                 ? "Last moved back \(last.date.formatted(date: .omitted, time: .shortened))"
                 : "Last move back failed \(last.date.formatted(date: .omitted, time: .shortened))")
        }

        Divider()

        Button("Move Dock Back Now") { model.moveBackNow() }
            .disabled(!model.hasPermission || model.pauseReason != nil)

        Picker("Pin To", selection: anchorBinding) {
            Text("Main Display").tag(String?.none)
            ForEach(model.displayMap.displays) { display in
                Text(display.name).tag(Optional(display.uuid))
            }
            if model.displayMap.anchorIsFallback {
                Text("Chosen Display (not connected)").tag(model.settings.anchorDisplayUUID)
            }
        }

        Toggle("Pause", isOn: pausedBinding)

        Toggle("Launch at Login", isOn: loginBinding)
            .onAppear { model.loginItem.refresh() }

        if !model.hasPermission {
            Button("Grant Permission…") { model.showOnboarding() }
        }

        Divider()

        Text("Hold Option to let the Dock move")

        if updater.updateAvailable {
            Button("Update Available…") { updater.checkForUpdates() }
        } else {
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheck)
        }

        Button("Quit SpectaDockPin") {
            model.shutdown()
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var anchorBinding: Binding<String?> {
        Binding(get: { model.settings.anchorDisplayUUID }, set: { model.setAnchor(uuid: $0) })
    }

    private var pausedBinding: Binding<Bool> {
        Binding(get: { model.settings.paused }, set: { model.setPaused($0) })
    }

    private var loginBinding: Binding<Bool> {
        Binding(get: { model.loginItem.isEnabled }, set: { model.loginItem.setEnabled($0) })
    }
}

/// The menu-bar icon: a template symbol per status.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        Image(systemName: model.status.symbolName)
            .accessibilityLabel(Text(model.status.headline))
    }
}
