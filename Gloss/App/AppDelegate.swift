//
//  AppDelegate.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import AppKit

/// Composition root: builds every service once (constructor injection, no singletons) and starts the app.
@MainActor
internal final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Properties

    internal let coordinator: AppCoordinator

    /// Unit tests run inside the app; they must not load the model or watch the user's selections.
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    // MARK: - Lifecycle

    override internal init() {
        let modelDirectory = ModelManifest.installDirectory
        let engine = TranslationEngine(modelDirectory: modelDirectory)
        let reader = AccessibilityReader()
        let settingsStore = SettingsStore(defaults: .standard)
        coordinator = AppCoordinator(
            settingsStore: settingsStore,
            accessibility: AccessibilityPermission(),
            clipboard: ClipboardPermission(),
            loginItem: LoginItem(),
            model: ModelManager(directory: modelDirectory, engine: engine, downloader: ModelDownloader()),
            updater: AppUpdater(),
            reader: reader,
            copyFallback: CopySelectionFallback(reader: reader),
            monitor: SelectionEventMonitor(),
            popup: PopupWindowController(model: PopupViewModel(engine: engine), settingsStore: settingsStore)
        )
        super.init()
    }

    // MARK: - NSApplicationDelegate

    internal func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        coordinator.start()
    }

    /// Opening Gloss again (Finder, Spotlight) shows a window, in case the menu bar icon is hidden by the notch.
    internal func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator.reopen()
        return false
    }

    /// Quits once the browsers Gloss switched to their full accessibility mode are switched back.
    internal func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !Self.isRunningTests else { return .terminateNow }
        Task {
            await coordinator.prepareToQuit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
