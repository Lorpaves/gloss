//
//  AppCoordinator.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import AppKit
import Observation
import os
import HyMTKit

/// An app other than Gloss that was recently in front, for the menu's per-app switch.
internal struct ExternalApp: Equatable, Sendable {
    internal var bundleID: String
    internal var name: String
}

/// Wires selection capture, language detection, the popup and the translation engine together.
@MainActor
@Observable
internal final class AppCoordinator {
    // MARK: - Properties

    /// The most recently active app other than Gloss.
    internal private(set) var lastExternalApp: ExternalApp?

    internal let settingsStore: SettingsStore
    internal let accessibility: AccessibilityPermission
    internal let clipboard: ClipboardPermission
    internal let loginItem: LoginItem
    internal let model: ModelManager
    internal let updater: AppUpdater

    @ObservationIgnored private let reader: AccessibilityReader
    @ObservationIgnored private let copyFallback: CopySelectionFallback
    @ObservationIgnored private let monitor: SelectionEventMonitor
    @ObservationIgnored private let popup: PopupWindowController
    @ObservationIgnored private var settingsWindow: SettingsWindowController?
    @ObservationIgnored private var onboardingWindow: OnboardingWindowController?
    @ObservationIgnored private var signalTask: Task<Void, Never>?
    @ObservationIgnored private var captureTask: Task<Void, Never>?
    @ObservationIgnored private var followTask: Task<Void, Never>?
    @ObservationIgnored private var followMode: FollowMode = .off
    /// Changes whenever following starts or stops, so late answers about an earlier selection are dropped.
    @ObservationIgnored private var followGeneration = 0
    @ObservationIgnored private var isReadingTrackedSelection = false
    @ObservationIgnored private var needsTrackedSelectionRead = false
    /// Where the followed selection was at the last read (Quartz coordinates), and when it last moved or was
    /// scrolled.
    @ObservationIgnored private var lastTrackedBounds: CGRect?
    @ObservationIgnored private var lastSelectionMovement: ContinuousClock.Instant?
    @ObservationIgnored private var permissionTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var isCapturing = false

    /// A selection farther than this from both ends of the press is a leftover the press didn't make.
    private static let proximity: CGFloat = 40
    /// Time allowed for asking an app for its selection.
    private static let readBudget = Duration.milliseconds(1200)
    /// Wait before asking an Electron app again while it builds its accessibility tree.
    private static let treeRetryDelay = Duration.milliseconds(350)
    /// How often the popup re-reads where its selection is while it stays put.
    private static let followInterval = Duration.milliseconds(100)
    /// The same while the selection is moving: about once per display frame.
    private static let movingFollowInterval = Duration.milliseconds(16)
    /// How long after the last movement that pace is kept; Chrome reports a scroll about 150 ms after it starts.
    private static let movingFollowDuration = Duration.milliseconds(500)
    /// How often a follow tick also checks that the same text is still selected.
    private static let textVerificationInterval = Duration.milliseconds(400)
    private static let logger = Logger.gloss("AppCoordinator")

    // MARK: - Lifecycle

    internal init(
        settingsStore: SettingsStore,
        accessibility: AccessibilityPermission,
        clipboard: ClipboardPermission,
        loginItem: LoginItem,
        model: ModelManager,
        updater: AppUpdater,
        reader: AccessibilityReader,
        copyFallback: CopySelectionFallback,
        monitor: SelectionEventMonitor,
        popup: PopupWindowController
    ) {
        self.settingsStore = settingsStore
        self.accessibility = accessibility
        self.clipboard = clipboard
        self.loginItem = loginItem
        self.model = model
        self.updater = updater
        self.reader = reader
        self.copyFallback = copyFallback
        self.monitor = monitor
        self.popup = popup
    }

    // MARK: - Startup

    /// Loads the model and starts watching selections as soon as Accessibility is granted. The first time, opens the
    /// welcome guide.
    internal func start() {
        Self.logger.notice("Starting; Accessibility trusted: \(self.accessibility.isTrusted)")
        model.start()
        updater.start()
        observeWorkspace()
        clipboard.startRefreshing()
        signalTask = Task { [weak self, monitor] in
            for await signal in monitor.signals {
                self?.handle(signal)
            }
        }
        if accessibility.isTrusted {
            beginCapturing()
        } else {
            // The first time, the welcome guide asks for the permission, after explaining what it's for.
            if settingsStore.hasCompletedOnboarding {
                accessibility.requestIfNeeded()
            }
            waitForAccessibility()
        }
        if !settingsStore.hasCompletedOnboarding {
            showOnboarding()
        }
    }

    // MARK: - Menu actions

    /// Whether the menu should offer clipboard access (the copy fallback only runs with "Always Allow").
    internal var needsClipboardAccess: Bool {
        settingsStore.settings.usesCopyFallback && !clipboard.isAllowed
    }

    /// Whether something keeps Gloss from translating, which the menu bar icon points out.
    internal var needsAttention: Bool {
        !accessibility.isTrusted || model.needsDownload || model.state == .loadFailed
    }

    internal func retryModelLoad() {
        model.retryLoad()
    }

    internal func downloadModel() {
        model.download(from: settingsStore.modelSource)
    }

    internal func openAccessibilitySettings() {
        accessibility.requestAccess()
    }

    internal func requestClipboardAccess() {
        clipboard.request()
    }

    /// Shows Settings, switched to `tab` if given.
    internal func showSettings(tab: SettingsWindowController.Tab? = nil) {
        let controller = settingsWindow ?? SettingsWindowController(
            settingsStore: settingsStore,
            accessibility: accessibility,
            clipboard: clipboard,
            loginItem: loginItem,
            model: model,
            updater: updater
        )
        settingsWindow = controller
        controller.show(tab: tab)
    }

    /// Opening Gloss again (Finder, Spotlight) shows the welcome guide until it's been gone through, and Settings
    /// after that.
    internal func reopen() {
        if onboardingWindow != nil || !settingsStore.hasCompletedOnboarding {
            showOnboarding()
        } else {
            showSettings()
        }
    }

    /// Shows the welcome guide.
    internal func showOnboarding() {
        if let onboardingWindow {
            onboardingWindow.show()
            return
        }
        let viewModel = OnboardingViewModel(
            accessibility: accessibility,
            clipboard: clipboard,
            model: model,
            settingsStore: settingsStore
        )
        let controller = OnboardingWindowController(viewModel: viewModel) { [weak self] in
            self?.onboardingDidClose()
        }
        onboardingWindow = controller
        controller.show()
    }

    /// Gives back the accessibility modes Gloss turned on in other apps; call before quitting.
    internal func prepareToQuit() async {
        await reader.restoreAccessibilityModes()
    }

    /// Whether selections in `app` are ignored.
    internal func isExcluded(_ app: ExternalApp) -> Bool {
        settingsStore.settings.isExcluded(app.bundleID)
    }

    /// Turns translation in `app` off, or back on.
    internal func toggleExclusion(of app: ExternalApp) {
        let exclude = !isExcluded(app)
        settingsStore.setExcluded(exclude, bundleID: app.bundleID)
        if exclude {
            popup.dismiss()
        }
    }

    // MARK: - Private: lifecycle

    /// The guide records itself as done when the user finishes it; closed before that, it opens again at the next
    /// launch or when Gloss is opened again.
    private func onboardingDidClose() {
        // Released once the window has finished closing, not from inside its own delegate call.
        Task { [weak self] in
            self?.onboardingWindow = nil
        }
    }

    private func waitForAccessibility() {
        permissionTask?.cancel()
        permissionTask = Task { [weak self] in
            do {
                try await self?.accessibility.waitUntilTrusted()
            } catch {
                // Cancelled: a newer wait replaced this one.
                return
            }
            self?.beginCapturing()
        }
    }

    private func beginCapturing() {
        guard !isCapturing else { return }
        isCapturing = true
        monitor.start()
        if let app = NSWorkspace.shared.frontmostApplication {
            applicationDidActivate(
                app.processIdentifier,
                bundleID: app.bundleIdentifier,
                name: app.localizedName,
                bundleURL: app.bundleURL
            )
        }
        Self.logger.notice("Watching selections")
    }

    private func accessibilityWasRevoked() {
        guard isCapturing else { return }
        isCapturing = false
        captureTask?.cancel()
        stopFollowing()
        monitor.stop()
        popup.dismiss()
        accessibility.markRevoked()
        Self.logger.notice("Accessibility was revoked; waiting for it to be granted again")
        waitForAccessibility()
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let processID = app?.processIdentifier else { return }
            let bundleID = app?.bundleIdentifier
            let name = app?.localizedName
            let bundleURL = app?.bundleURL
            MainActor.assumeIsolated {
                self?.applicationDidActivate(processID, bundleID: bundleID, name: name, bundleURL: bundleURL)
            }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.popup.dismissUnlessPinned()
            }
        })
    }

    private func applicationDidActivate(_ processID: pid_t, bundleID: String?, name: String?, bundleURL: URL?) {
        guard processID != ProcessInfo.processInfo.processIdentifier else { return }
        if let bundleID {
            lastExternalApp = ExternalApp(bundleID: bundleID, name: name ?? bundleID)
        }
        popup.dismissUnlessPinned()
        let settings = settingsStore.settings
        guard isCapturing, settings.isEnabled, !settings.isExcluded(bundleID) else { return }
        Task { [reader] in
            await reader.enableAccessibilityTree(for: processID, bundleURL: bundleURL)
        }
    }

    // MARK: - Private: selection pipeline

    private func handle(_ signal: SelectionSignal) {
        switch signal {
        case .pointerDown:
            captureTask?.cancel()
            popup.dismissUnlessPinned()
            if !popup.isFollowingSelection {
                stopFollowing()
            }
        case .scroll(let location):
            followScroll(at: location)
        case .pointerUp(let down, let up):
            let settings = settingsStore.settings
            guard isCapturing, settings.isEnabled else { return }
            guard model.acceptsSelections else {
                Self.logger.debug("Ignored press: the model isn't ready")
                return
            }
            guard let gesture = SelectionGesture.classify(down: down, up: up) else {
                if let rejection = SelectionGesture.rejection(down: down, up: up), rejection != .plainClick {
                    Self.logger.debug("Ignored press: \(rejection.rawValue, privacy: .public)")
                }
                return
            }
            captureTask?.cancel()
            captureTask = Task { [weak self] in
                await self?.capture(gesture, down: down, up: up, settings: settings)
            }
        case .keyboardSelection(let key):
            let settings = settingsStore.settings
            guard isCapturing, settings.isEnabled else { return }
            guard model.acceptsSelections else {
                Self.logger.debug("Ignored keys: the model isn't ready")
                return
            }
            captureTask?.cancel()
            captureTask = Task { [weak self] in
                await self?.capture(key, settings: settings)
            }
        }
    }

    private func capture(
        _ gesture: SelectionGesture,
        down: PointerDownContext,
        up: PointerUpContext,
        settings: GlossSettings
    ) async {
        do {
            try await Task.sleep(for: gesture.settleDelay)
            guard let selection = try await readSelection(gesture: gesture, down: down, up: up, settings: settings) else {
                return
            }
            try Task.checkCancellation()
            show(selection, press: Press(down: down, up: up), settings: settings)
        } catch is CancellationError {
            // A newer press replaced this one.
            return
        } catch {
            Self.logger.error("Selection capture failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func capture(_ key: SelectionKey, settings: GlossSettings) async {
        do {
            try await Task.sleep(for: key.settleDelay)
            guard let selection = try await readKeyboardSelection(settings: settings) else { return }
            try Task.checkCancellation()
            show(selection, press: nil, settings: settings)
        } catch is CancellationError {
            // A newer press or key replaced this one.
            return
        } catch {
            Self.logger.error("Selection capture failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func readSelection(
        gesture: SelectionGesture,
        down: PointerDownContext,
        up: PointerUpContext,
        settings: GlossSettings
    ) async throws -> CapturedSelection? {
        let processID: pid_t
        let isVerified: Bool
        switch await reader.target(
            at: down.sample.quartzLocation,
            frontmostProcessID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            windowOwnerProcessID: down.windowID.flatMap(ScreenGeometry.ownerProcessID(of:))
        ) {
        case .accepted(let accepted, let verified):
            processID = accepted
            isVerified = verified
        case .rejected(let reason):
            Self.logger.debug("Ignored press: \(reason, privacy: .public)")
            return nil
        case .apiDisabled:
            accessibilityWasRevoked()
            return nil
        }
        let bundleID = NSRunningApplication(processIdentifier: processID)?.bundleIdentifier
        guard !settings.isExcluded(bundleID) else {
            Self.logger.debug("Ignored press in excluded app \(bundleID ?? "?", privacy: .public)")
            return nil
        }

        switch try await accessibilitySelection(processID: processID, near: up.sample.quartzLocation) {
        case .selection(let selection):
            return selection
        case .nothing:
            return nil
        case .unsupported:
            break
        }
        // A press the app couldn't place may not have been on text at all, so it doesn't get to copy either.
        guard settings.usesCopyFallback, gesture.allowsCopyFallback, isVerified else {
            Self.logger.debug("Selection not readable through Accessibility; copy fallback not used")
            return nil
        }
        guard let text = try await copyFallback.copySelection(processID: processID, bundleID: bundleID) else {
            return nil
        }
        Self.logger.debug("Read \(text.count) characters through the Copy menu")
        return CapturedSelection(text: text, processID: processID, bounds: nil, source: .copy)
    }

    /// Reads what a key press selected in the app that has the keyboard focus.
    ///
    /// Only through Accessibility: ⌘A or Shift with the arrow keys in a list selects rows, and the Copy menu would
    /// then copy those.
    private func readKeyboardSelection(settings: GlossSettings) async throws -> CapturedSelection? {
        let frontmostProcessID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let processID = await reader.focusedProcessID(frontmostProcessID: frontmostProcessID),
              processID != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        let bundleID = NSRunningApplication(processIdentifier: processID)?.bundleIdentifier
        guard !settings.isExcluded(bundleID) else {
            Self.logger.debug("Ignored keys in excluded app \(bundleID ?? "?", privacy: .public)")
            return nil
        }
        switch try await accessibilitySelection(processID: processID, near: nil) {
        case .selection(let selection):
            return selection
        case .nothing:
            return nil
        case .unsupported:
            Self.logger.debug("Selection not readable through Accessibility; copy fallback not used for keys")
            return nil
        }
    }

    /// Reads an app's selection through Accessibility.
    /// - Parameters:
    ///   - processID: The app.
    ///   - point: Where the press ended (Quartz coordinates); `nil` for a selection made with the keyboard.
    private func accessibilitySelection(processID: pid_t, near point: CGPoint?) async throws -> AccessibilityRead {
        var result = try await reader.readSelection(
            processID: processID,
            near: point,
            deadline: .now + Self.readBudget
        )
        // An app that just turned its accessibility tree on may not expose the selection, or its position, yet.
        switch result {
        case .unsupported, .text(_, bounds: .none, clipFrames: _, isCorrected: _):
            if await reader.isTreeWarmingUp(for: processID) {
                try await Task.sleep(for: Self.treeRetryDelay)
                result = try await reader.readSelection(
                    processID: processID,
                    near: point,
                    deadline: .now + Self.readBudget
                )
            }
        case .text, .empty, .apiDisabled:
            break
        }

        switch result {
        case .text(let text, let bounds, let clipFrames, let isCorrected):
            Self.logger.debug("Read \(text.count) characters through Accessibility")
            return .selection(CapturedSelection(
                text: text,
                processID: processID,
                bounds: bounds,
                clipFrames: clipFrames,
                isPositionCorrected: isCorrected,
                source: .accessibility
            ))
        case .empty:
            Self.logger.debug("Nothing selected")
            return .nothing
        case .apiDisabled:
            accessibilityWasRevoked()
            return .nothing
        case .unsupported:
            return .unsupported
        }
    }

    /// Shows the popup for a selection.
    /// - Parameter press: The press that made the selection; `nil` for one made with the keyboard.
    private func show(_ selection: CapturedSelection, press: Press?, settings: GlossSettings) {
        let text = selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var bounds = selection.bounds
            .map { ScreenGeometry.flipped($0, primaryScreenHeight: primaryHeight) }
            .flatMap { ScreenGeometry.isMeasurable($0) ? $0 : nil }
        var reportedClipFrames = selection.clipFrames
        if let reported = bounds, let press {
            let isNearPress = ScreenGeometry.isPoint(press.down.sample.cocoaLocation, near: reported, within: Self.proximity)
                || ScreenGeometry.isPoint(press.up.sample.cocoaLocation, near: reported, within: Self.proximity)
            if !isNearPress {
                guard selection.isPositionCorrected else {
                    Self.logger.debug("Ignored a selection far from the press (left over from earlier)")
                    return
                }
                // A position Gloss had to work out may be wrong, and then this is the selection the press made.
                Self.logger.debug("The worked-out position is far from the press; position ignored")
                bounds = nil
                reportedClipFrames = []
            }
        }
        if popup.isPresented, popup.model.sourceText == text {
            return
        }

        switch TriggerRule.evaluate(text, settings: settings) {
        case .ignore:
            Self.logger.debug("Ignored \(text.count) characters: not a language to translate")
            return
        case .tooLong:
            popup.model.showTooLong(text)
        case .translate(let language):
            Self.logger.debug("Translating \(text.count) characters from \(language.rawValue, privacy: .public)")
            popup.model.translate(text, from: language, to: settings.targetLanguage)
        }

        // Anchor to the part of the selection that is in view; without bounds, to the span of the press (from
        // where it started to where it ended), never to the pointer alone.
        let screenFrames = NSScreen.screens.map(\.frame)
        let windowID = press?.down.windowID
        let windowFrame = (press?.down.windowBounds ?? ScreenGeometry.frontWindowBounds(ofProcess: selection.processID))
            .map { ScreenGeometry.flipped($0, primaryScreenHeight: primaryHeight) }
        let clipFrames = self.clipFrames(reported: reportedClipFrames, windowID: windowID)
        let selectionRect = bounds
            .flatMap { ScreenGeometry.visiblePart(of: $0, clippedBy: clipFrames) }
            .flatMap { ScreenGeometry.isUsableAnchor($0, screenFrames: screenFrames) ? $0 : nil }
        let anchor: CGRect
        if let selectionRect {
            anchor = selectionRect
        } else if let press {
            anchor = ScreenGeometry.pressAnchor(from: press.down.sample.cocoaLocation, to: press.up.sample.cocoaLocation)
        } else {
            anchor = ScreenGeometry.keyboardAnchor(pointer: NSEvent.mouseLocation, windowFrame: windowFrame)
        }
        popup.present(anchor: anchor, leadingX: anchor.minX - PopupLayout.contentInset, followsSelection: true)
        if selectionRect != nil {
            startFollowing(.accessibility(windowID: windowID))
        } else {
            startFollowing(.untracked(windowFrame: windowFrame))
        }
    }

    // MARK: - Private: following the selection

    /// Moves the popup with its selection until it is dismissed, pinned or dragged.
    private func startFollowing(_ mode: FollowMode) {
        followTask?.cancel()
        followTask = nil
        followMode = mode
        followGeneration += 1
        lastTrackedBounds = nil
        lastSelectionMovement = nil
        monitor.reportsScrolling = true
        guard case .accessibility = mode else {
            Task { [reader] in
                await reader.stopTrackingSelection()
            }
            return
        }
        // Scrolling triggers reads right away; this also catches keyboard scrolling, window moves and reflowed
        // text, and notices when a different text gets selected.
        followTask = Task { [weak self] in
            var lastVerification = ContinuousClock.now
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: self?.followPollInterval ?? Self.followInterval)
                } catch {
                    return
                }
                guard let self, self.popup.isFollowingSelection else { return }
                let now = ContinuousClock.now
                let verifiesText = now - lastVerification >= Self.textVerificationInterval
                if verifiesText {
                    lastVerification = now
                }
                self.readTrackedSelection(verifiesText: verifiesText)
            }
        }
    }

    /// Short while the selection is moving, so the popup keeps up with every frame of a scroll.
    private var followPollInterval: Duration {
        guard let lastSelectionMovement,
              ContinuousClock.now - lastSelectionMovement < Self.movingFollowDuration
        else { return Self.followInterval }
        return Self.movingFollowInterval
    }

    private func stopFollowing() {
        followTask?.cancel()
        followTask = nil
        followMode = .off
        followGeneration += 1
        lastTrackedBounds = nil
        lastSelectionMovement = nil
        monitor.reportsScrolling = false
        Task { [reader] in
            await reader.stopTrackingSelection()
        }
    }

    /// Keeps the popup on its selection while the user scrolls.
    /// - Parameter location: Where the pointer was (Cocoa coordinates).
    private func followScroll(at location: CGPoint) {
        guard popup.isFollowingSelection else {
            stopFollowing()
            return
        }
        switch followMode {
        case .off:
            monitor.reportsScrolling = false
        case .accessibility:
            lastSelectionMovement = .now
            readTrackedSelection(verifiesText: false)
        case .untracked(let windowFrame):
            // Scrolling another window doesn't move the selection.
            if let windowFrame, !windowFrame.contains(location) {
                return
            }
            // The text moves, but nothing tells where to: close the popup rather than leave it pointing elsewhere.
            Self.logger.debug("Scrolled an untracked selection; closing the popup")
            popup.dismissUnlessPinned()
            stopFollowing()
        }
    }

    /// Re-reads where the selection is. Requests made while a read is running are merged into one more read, so a
    /// burst of scroll events doesn't queue up calls into the app.
    private func readTrackedSelection(verifiesText: Bool) {
        guard case .accessibility = followMode, popup.isFollowingSelection else { return }
        guard !isReadingTrackedSelection else {
            needsTrackedSelectionRead = true
            return
        }
        isReadingTrackedSelection = true
        let generation = followGeneration
        Task { [weak self, reader] in
            let state = await reader.trackedSelectionState(verifiesText: verifiesText)
            guard let self else { return }
            self.isReadingTrackedSelection = false
            // A newer selection may have started in the meantime; this answer is about the old one.
            if generation == self.followGeneration {
                self.applyTrackedSelection(state)
            }
            if self.needsTrackedSelectionRead {
                self.needsTrackedSelectionRead = false
                self.readTrackedSelection(verifiesText: false)
            }
        }
    }

    private func applyTrackedSelection(_ state: AccessibilityReader.TrackedSelectionState) {
        switch state {
        case .located(let bounds, let reportedClipFrames):
            guard case .accessibility(let windowID) = followMode else { return }
            if bounds != lastTrackedBounds {
                if lastTrackedBounds != nil {
                    lastSelectionMovement = .now
                }
                lastTrackedBounds = bounds
            }
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            popup.follow(
                selectionBounds: ScreenGeometry.flipped(bounds, primaryScreenHeight: primaryHeight),
                clipFrames: clipFrames(reported: reportedClipFrames, windowID: windowID)
            )
        case .changed:
            Self.logger.debug("Selection changed; closing the popup")
            popup.dismissUnlessPinned()
            stopFollowing()
        case .unavailable:
            break
        }
    }

    /// What clips a selection (Cocoa coordinates): the frames its app reported, or else the window it was made in.
    /// - Parameters:
    ///   - reported: Frames of the scroll areas or window around the selection (Quartz coordinates).
    ///   - windowID: The window the press started in.
    private func clipFrames(reported: [CGRect], windowID: CGWindowID?) -> [CGRect] {
        var frames = reported
        if frames.isEmpty, let windowID, let windowBounds = ScreenGeometry.windowBounds(of: windowID) {
            frames = [windowBounds]
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return frames.map { ScreenGeometry.flipped($0, primaryScreenHeight: primaryHeight) }
    }
}

// MARK: - Press

/// A press of the pointer, from button down to button up.
private struct Press {
    var down: PointerDownContext
    var up: PointerUpContext
}

// MARK: - AccessibilityRead

/// What asking an app for its selection through Accessibility came to.
private enum AccessibilityRead {
    case selection(CapturedSelection)
    /// Nothing is selected, or Gloss lost its permission.
    case nothing
    /// The app doesn't expose its selection that way.
    case unsupported
}

// MARK: - FollowMode

/// How the popup keeps up with its selection.
private enum FollowMode {
    case off
    /// The app reports where the selection is: re-read it on every scroll and regularly in between. The window
    /// the selection was made in stands in for what clips it when the app doesn't tell.
    case accessibility(windowID: CGWindowID?)
    /// The app doesn't (the copy fallback): scrolling the selection's window closes the popup.
    case untracked(windowFrame: CGRect?)
}
