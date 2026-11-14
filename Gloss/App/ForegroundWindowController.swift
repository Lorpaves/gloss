//
//  ForegroundWindowController.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/14.
//

import Foundation
import AppKit

/// A window Gloss shows in front of every other app, with the keyboard focus: Settings and the welcome guide.
///
/// Gloss has no Dock icon, so it becomes a regular app while such a window is open; otherwise the window could open
/// behind other apps and couldn't be reached with ⌘Tab.
@MainActor
internal class ForegroundWindowController: NSWindowController, NSWindowDelegate {
    // MARK: - Properties

    private var activationTask: Task<Void, Never>?

    /// How often, and how many times, the window asks for the focus until it has it.
    private static let activationInterval = Duration.milliseconds(100)
    private static let activationAttempts = 10

    // MARK: - Lifecycle

    override internal init(window: NSWindow?) {
        super.init(window: window)
        window?.delegate = self
        window?.isReleasedWhenClosed = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Actions

    /// Brings the window in front of every other app and gives it the keyboard focus.
    internal func show() {
        NSApp.setActivationPolicy(.regular)
        showWindow(nil)
        // In front right away, even before Gloss is the active app.
        window?.orderFrontRegardless()
        activationTask?.cancel()
        activationTask = Task { [weak self] in
            await self?.takeFocus()
        }
    }

    // MARK: - NSWindowDelegate

    internal func windowWillClose(_ notification: Notification) {
        activationTask?.cancel()
        // Stays a regular app while another of these windows is open.
        let othersAreOpen = NSApp.windows.contains { other in
            other !== window && other.isVisible && other.delegate is ForegroundWindowController
        }
        if !othersAreOpen {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Private

    /// Makes Gloss the active app and the window the key one.
    ///
    /// One request isn't enough: the menu bar menu that opened the window is still closing and hands the focus back
    /// to the app that had it. So the window asks again until it holds the focus.
    private func takeFocus() async {
        for _ in 0..<Self.activationAttempts {
            guard let window, window.isVisible else { return }
            if NSApp.isActive, window.isKeyWindow {
                return
            }
            (NSApp as any ForcedActivation).activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            do {
                try await Task.sleep(for: Self.activationInterval)
            } catch {
                // The window closed or was asked to show again.
                return
            }
        }
    }
}

// MARK: - ForcedActivation

/// `NSApplication.activate(ignoringOtherApps:)`, reached without its deprecation warning.
///
/// Its replacement, `activate()`, only asks: macOS doesn't grant the focus to an app without a Dock icon that another
/// app is in front of, and the window would open behind that app, without the keyboard.
@MainActor
private protocol ForcedActivation {
    func activate(ignoringOtherApps: Bool)
}

extension NSApplication: ForcedActivation {}
