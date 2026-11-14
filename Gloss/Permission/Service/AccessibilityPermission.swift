//
//  AccessibilityPermission.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import AppKit
import ApplicationServices
import Observation

/// Accessibility trust, needed to read other apps' selections and to intercept Esc.
@MainActor
@Observable
internal final class AccessibilityPermission {
    // MARK: - Properties

    /// Whether Gloss is allowed to use the Accessibility API.
    internal private(set) var isTrusted: Bool

    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )

    // MARK: - Lifecycle

    internal init() {
        isTrusted = AXIsProcessTrusted()
    }

    // MARK: - Actions

    /// Shows the system prompt once, which also lists Gloss under Privacy & Security ▸ Accessibility.
    internal func requestIfNeeded() {
        // The literal avoids the C global `kAXTrustedCheckOptionPrompt`, a `var` Swift 6 rejects.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
    }

    /// Lists Gloss under Privacy & Security ▸ Accessibility and opens that page, where the user turns it on.
    ///
    /// The first request in a while also shows the system's prompt; the page opens either way, since macOS doesn't
    /// repeat the prompt.
    internal func requestAccess() {
        requestIfNeeded()
        guard !isTrusted else { return }
        openSystemSettings()
    }

    /// Opens System Settings ▸ Privacy & Security ▸ Accessibility.
    internal func openSystemSettings() {
        guard let url = Self.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Returns once Gloss is trusted; the grant takes effect without relaunching.
    /// - Throws: `CancellationError` when the waiting task is cancelled.
    internal func waitUntilTrusted() async throws {
        while !AXIsProcessTrusted() {
            try await Task.sleep(for: .seconds(1))
        }
        isTrusted = true
    }

    /// Records that an Accessibility call reported the API as disabled (the user revoked the permission).
    internal func markRevoked() {
        isTrusted = false
    }
}
