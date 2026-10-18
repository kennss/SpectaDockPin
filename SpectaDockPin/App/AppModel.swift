//
//  @file        AppModel.swift
//  @description The one place that decides (DESIGN §5.8): it gathers permission, displays, Dock settings,
//               the Dock's position and session events, keeps the guard's snapshot current, and starts,
//               retries or stops relocations. The menu reads its status.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-10-18
//  @lastUpdated 2026-10-18
//
//  Notes:
//  - Owned by AppDelegate, so start() and shutdown() are tied to launch and quit. A unit-test host never
//    starts (I7): no tap, no cursor movement, no watchers.
//  - Order on permission loss: EdgeGuard.stop() first, then everything else (I4).
//  - The guard never blocks the row of the display the Dock is on when the user moved it there with Option
//    (userOverride): with autohide that row is how the user reveals the Dock.
//  - Retries after a failed drive follow PinTuning.retryDelays; after the last one the status stays
//    `.failed` until a new event (wake, unlock, display change, Dock relaunch, "Move Dock Back Now") — the
//    3-second poll alone never restarts attempts, so a Dock that will not move does not get the cursor
//    hijacked forever.
//  - "Today" counts are measured from the guard's running totals and reset at local midnight.
//

import AppKit
import CoreGraphics

/// Why pinning is switched off for now (I6).
enum PauseReason: Sendable, Equatable {
    case userPaused
    case singleDisplay
    case dockOnSide(DockOrientation)
    case sharedSpaces
}

enum PinStatus: Sendable, Equatable {
    case starting
    case needsPermission
    case paused(PauseReason)
    case pinned(anchorName: String)
    case movedByUser(displayName: String)
    /// The Dock is on another display and a relocation is about to start.
    case dockAway(displayName: String)
    case waiting(WaitReason)
    case relocating
    /// A drive failed; the next attempt follows PinTuning.retryDelays.
    case retrying(attempt: Int)
    case failed(attempts: Int)
    case dockNotFound
}

enum RelocationPhase: Sendable, Equatable {
    case idle
    case waiting(WaitReason)
    case driving
    case retrying(attempt: Int)
    case failed(attempts: Int)
}

@MainActor
@Observable
final class AppModel {
    let settings = AppSettings()
    let loginItem = LoginItem()

    private(set) var displayMap = DisplayMap.empty
    private(set) var dockSettings = DockSettings()
    private(set) var dockPlacement = DockPlacement.unknown
    private(set) var hasPermission = false
    private(set) var phase = RelocationPhase.idle
    private(set) var userOverride = false
    private(set) var blockedToday = 0
    private(set) var lastRelocation: (date: Date, succeeded: Bool)?
    private(set) var started = false
    private(set) var dockChecked = false

    @ObservationIgnored private let edgeGuard = EdgeGuard()
    @ObservationIgnored private let locator = DockLocator()
    @ObservationIgnored private lazy var relocator = Relocator(locator: locator, edgeGuard: edgeGuard)
    @ObservationIgnored private let displayWatcher = DisplayWatcher()
    @ObservationIgnored private let sessionMonitor = SessionMonitor()
    @ObservationIgnored private let permissionWatch = PermissionWatch()
    @ObservationIgnored private let onboarding = OnboardingWindow()

    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var relocationTask: Task<Void, Never>?
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private var checkInFlight = false
    @ObservationIgnored private var failedAttempts = 0
    @ObservationIgnored private var blockedBaseline = 0
    @ObservationIgnored private var blockedDay = Calendar.current.startOfDay(for: Date())

    // MARK: - Lifecycle

    func start() {
        guard !started, !AppRuntime.isUnitTestHost else { return }
        started = true
        AppLog.session.info("starting")

        hasPermission = permissionWatch.isTrusted
        permissionWatch.onChange = { [weak self] trusted in self?.permissionChanged(trusted) }
        permissionWatch.start()

        rebuildDisplayMap()
        displayWatcher.onChange = { [weak self] in self?.displaysChanged() }
        displayWatcher.start()

        dockSettings = DockPreferences.read()

        sessionMonitor.onEvent = { [weak self] event in self?.sessionEvent(event) }
        sessionMonitor.start()

        if hasPermission {
            startGuard()
        } else {
            onboarding.show(model: self)
        }
        startTicking()
        Task { await checkDock(trigger: .event) }
    }

    /// Stops everything, the tap first. Safe to call more than once (Quit menu and applicationWillTerminate).
    func shutdown() {
        edgeGuard.stop()
        relocationTask?.cancel()
        settleTask?.cancel()
        tickTask?.cancel()
        permissionWatch.stop()
        displayWatcher.stop()
        sessionMonitor.stop()
        started = false
    }

    // MARK: - User actions

    func setAnchor(uuid: String?) {
        settings.anchorDisplayUUID = uuid
        rebuildDisplayMap()
        userOverride = false
        Task { await checkDock(trigger: .event) }
    }

    func setPaused(_ paused: Bool) {
        settings.paused = paused
        if paused { relocationTask?.cancel() }
        applySnapshot()
        Task { await checkDock(trigger: .event) }
    }

    func moveBackNow() {
        userOverride = false
        failedAttempts = 0
        if case .failed = phase { phase = .idle }
        applySnapshot()
        Task { await checkDock(trigger: .event) }
    }

    func requestPermission() {
        permissionWatch.request()
    }

    func showOnboarding() {
        onboarding.show(model: self)
    }

    // MARK: - Status

    var pauseReason: PauseReason? {
        if settings.paused { return .userPaused }
        if displayMap.displays.count < 2 { return .singleDisplay }
        if dockSettings.orientation != .bottom { return .dockOnSide(dockSettings.orientation) }
        if !dockSettings.separateSpaces { return .sharedSpaces }
        return nil
    }

    var status: PinStatus {
        guard started else { return .starting }
        if !hasPermission { return .needsPermission }
        if let pauseReason { return .paused(pauseReason) }
        switch phase {
        case .failed(let attempts): return .failed(attempts: attempts)
        case .driving: return .relocating
        case .retrying(let attempt) where !isDockOnAnchor: return .retrying(attempt: attempt)
        case .waiting(let reason) where !isDockOnAnchor: return .waiting(reason)
        case .idle, .waiting, .retrying: break
        }
        switch dockPlacement {
        case .display(let id) where id == displayMap.anchor?.id:
            return .pinned(anchorName: displayMap.anchor?.name ?? "")
        case .display(let id):
            let name = displayMap.display(id: id)?.name ?? ""
            return userOverride ? .movedByUser(displayName: name) : .dockAway(displayName: name)
        case .unknown:
            return dockChecked ? .dockNotFound : .starting
        }
    }

    var isDockOnAnchor: Bool {
        guard let anchor = displayMap.anchor else { return false }
        return dockPlacement == .display(anchor.id)
    }

    // MARK: - Events

    private enum CheckTrigger {
        /// Something happened: a failed state may start over.
        case event
        /// The periodic check.
        case poll
    }

    private func permissionChanged(_ trusted: Bool) {
        if !trusted {
            edgeGuard.stop()   // I4: before anything else
            relocationTask?.cancel()
            hasPermission = false
            applySnapshot()
            return
        }
        hasPermission = true
        startGuard()
        Task { await checkDock(trigger: .event) }
    }

    private func displaysChanged() {
        rebuildDisplayMap()
        userOverride = false
        scheduleSettledCheck()
    }

    private func sessionEvent(_ event: SessionEvent) {
        switch event {
        case .willSleep, .screenLocked, .sessionResigned:
            relocationTask?.cancel()
        case .didWake, .screenUnlocked, .sessionActivated:
            userOverride = false
            scheduleSettledCheck()
        case .dockRelaunched:
            locator.invalidate()
            scheduleSettledCheck()
        case .spaceChanged:
            Task { await checkDock(trigger: .event) }
        }
    }

    private func scheduleSettledCheck() {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: PinTuning.settleAfterSessionChange)
            guard !Task.isCancelled else { return }
            self?.dockSettings = DockPreferences.read()
            await self?.checkDock(trigger: .event)
        }
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                tick += 1
                guard let self else { return }
                self.updateBlockedCount()
                if tick % Int(PinTuning.tapCheckInterval) == 0, self.edgeGuard.reenableIfDisabled() {
                    AppLog.guardTap.notice("safety net re-enabled the tap")
                }
                if tick % Int(PinTuning.pollInterval) == 0 {
                    let settings = DockPreferences.read()
                    if settings != self.dockSettings { self.dockSettings = settings }
                    await self.checkDock(trigger: .poll)
                }
            }
        }
    }

    // MARK: - Decisions

    private func startGuard() {
        guard hasPermission, !edgeGuard.isRunning else { return }
        if !edgeGuard.start() {
            AppLog.guardTap.error("trusted, but the tap could not be created")
        }
        applySnapshot()
    }

    private func rebuildDisplayMap() {
        displayMap = DisplayMap(displays: DisplayWatcher.activeDisplays(),
                                preferredAnchorUUID: settings.anchorDisplayUUID)
        applySnapshot()
    }

    /// Pushes the current rows and on/off state to the tap thread.
    private func applySnapshot() {
        let active = hasPermission && pauseReason == nil && edgeGuard.isRunning
        var overrideDisplay: CGDirectDisplayID?
        if userOverride, case .display(let id) = dockPlacement { overrideDisplay = id }
        edgeGuard.update(GuardSnapshot(isActive: active,
                                       strips: active ? displayMap.triggerStrips(alsoExcluding: overrideDisplay) : []))
    }

    private func checkDock(trigger: CheckTrigger) async {
        guard started, !checkInFlight else { return }
        checkInFlight = true
        defer { checkInFlight = false }

        let window = await locator.current()
        let placement = window.map { DockLocator.placement(of: $0.bounds, in: displayMap.displays) } ?? .unknown
        if placement != dockPlacement {
            AppLog.dock.info("Dock placement \(String(describing: placement), privacy: .public)")
        }
        dockPlacement = placement
        dockChecked = true

        guard hasPermission, pauseReason == nil, let anchor = displayMap.anchor else {
            applySnapshot()
            return
        }
        switch placement {
        case .display(let id) where id == anchor.id:
            userOverride = false
            failedAttempts = 0
            if phase != .driving { phase = .idle }
        case .display(let id):
            if !userOverride, movedWithOption(to: id) {
                userOverride = true
                AppLog.dock.info("Dock moved with Option; leaving it")
            }
            if userOverride { break }
            if case .failed = phase {
                guard trigger == .event else { break }
                failedAttempts = 0
                phase = .idle
            }
            startRelocation()
        case .unknown:
            break
        }
        applySnapshot()
    }

    private func movedWithOption(to displayID: CGDirectDisplayID) -> Bool {
        guard let pass = edgeGuard.status.lastOptionPass,
              ProcessInfo.processInfo.systemUptime - pass.time <= PinTuning.optionOverrideWindow
        else { return false }
        return displayMap.display(containing: pass.location)?.id == displayID
    }

    private func startRelocation() {
        guard relocationTask == nil else { return }
        relocationTask = Task { [weak self] in
            await self?.runRelocation()
            self?.relocationTask = nil
        }
    }

    private func relocationInputs() -> RelocationInputs {
        let anyInput = CGEventType(rawValue: ~UInt32(0)) ?? .mouseMoved
        let buttons: [CGMouseButton] = [.left, .right, .center]
        return RelocationInputs(
            hasPermission: hasPermission,
            paused: pauseReason != nil,
            userOverride: userOverride,
            asleep: sessionMonitor.isAsleep,
            screenLocked: sessionMonitor.isScreenLocked,
            onConsole: sessionMonitor.isOnConsole,
            buttonDown: buttons.contains { CGEventSource.buttonState(.hidSystemState, button: $0) },
            secondsSinceInput: CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
        )
    }

    private func runRelocation() async {
        while !Task.isCancelled {
            switch RelocationPolicy.decide(relocationInputs()) {
            case .wait(let reason):
                phase = .waiting(reason)
                guard reason.isShortLived else { return }
                try? await Task.sleep(for: PinTuning.waitRecheckInterval)
                continue
            case .go:
                break
            }
            guard let target = displayMap.relocationPoint, let anchor = displayMap.anchor else { return }
            let displays = displayMap.displays

            phase = .driving
            let outcome = await relocator.drive(to: target) { bounds in
                DockLocator.placement(of: bounds, in: displays) == .display(anchor.id)
            }
            switch outcome {
            case .arrived:
                phase = .idle
                failedAttempts = 0
                lastRelocation = (Date(), true)
                dockPlacement = .display(anchor.id)
                applySnapshot()
                return
            case .abortedByUser:
                phase = .waiting(.userActive)
                continue
            case .cancelled:
                phase = .idle
                return
            case .timedOut:
                failedAttempts += 1
                lastRelocation = (Date(), false)
                AppLog.relocate.notice("attempt \(self.failedAttempts) failed")
                guard failedAttempts <= PinTuning.retryDelays.count else {
                    phase = .failed(attempts: failedAttempts)
                    return
                }
                phase = .retrying(attempt: failedAttempts + 1)
                try? await Task.sleep(for: PinTuning.retryDelays[failedAttempts - 1])
                if let window = await locator.current(),
                   DockLocator.placement(of: window.bounds, in: displayMap.displays) == .display(anchor.id) {
                    phase = .idle
                    failedAttempts = 0
                    dockPlacement = .display(anchor.id)
                    return
                }
            }
        }
    }

    private func updateBlockedCount() {
        let total = edgeGuard.status.blockedVisits
        let today = Calendar.current.startOfDay(for: Date())
        if today != blockedDay {
            blockedDay = today
            blockedBaseline = total
        }
        let count = total - blockedBaseline
        if count != blockedToday { blockedToday = count }
    }
}
