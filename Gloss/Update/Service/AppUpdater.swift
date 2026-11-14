//
//  AppUpdater.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/14.
//

import Foundation
import Observation
import Sparkle

/// Checks for new versions of Gloss and installs them, through Sparkle (feed and public key are in `Info.plist`).
///
/// Gloss lives in the menu bar, so an update found by a scheduled check doesn't open over whatever the user is
/// doing: it waits as ``availableVersion``, which the menu points out, until the user asks to see it.
@MainActor
@Observable
internal final class AppUpdater: NSObject {
    // MARK: - Properties

    /// Version of an update a scheduled check found and the user hasn't looked at yet.
    internal private(set) var availableVersion: String?
    /// Whether a check can start now; `false` while one is running.
    internal private(set) var canCheckForUpdates = false
    /// Whether Gloss looks for updates by itself, once a day.
    internal var automaticallyChecksForUpdates = true {
        didSet {
            guard automaticallyChecksForUpdates != oldValue else { return }
            controller?.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    /// The version of Gloss that is running, e.g. "1.0".
    internal let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    // MARK: - Lifecycle

    override internal init() {
        super.init()
        // Not started here: unit tests build the app's services too, and must not reach the network.
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
    }

    // MARK: - Actions

    /// Starts the scheduled checks; call once at launch.
    internal func start() {
        guard let controller, observation == nil else { return }
        controller.startUpdater()
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            guard let canCheck = change.newValue else { return }
            Task { @MainActor [weak self] in
                self?.canCheckForUpdates = canCheck
            }
        }
    }

    /// Checks now and shows the result, or brings up the update that is waiting.
    internal func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

// MARK: - SPUStandardUserDriverDelegate

// Sparkle calls its user driver's delegate on the main thread, though the protocol doesn't say so to Swift.
extension AppUpdater: @preconcurrency SPUStandardUserDriverDelegate {
    internal var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    /// Sparkle shows a scheduled update itself only when Gloss already has the user's attention.
    internal func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    internal func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        // Left to Gloss: the menu shows it until the user picks it up.
        if !handleShowingUpdate {
            availableVersion = update.displayVersionString
        }
    }

    internal func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableVersion = nil
    }

    internal func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
    }
}
