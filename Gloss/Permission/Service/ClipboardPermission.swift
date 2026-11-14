//
//  ClipboardPermission.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import AppKit
import Observation
import os

/// Whether Gloss may read the general pasteboard without the system's paste alert (macOS 15.4+ pasteboard privacy).
///
/// The copy fallback only runs when this is `.alwaysAllow`, so the alert never interrupts reading.
@MainActor
@Observable
internal final class ClipboardPermission {
    // MARK: - Properties

    /// Whether reads are always allowed.
    internal private(set) var isAllowed: Bool

    @ObservationIgnored private let pasteboard: NSPasteboard
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard"
    )
    private static let logger = Logger.gloss("ClipboardPermission")

    // MARK: - Lifecycle

    internal init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        isAllowed = pasteboard.allowsReadingWithoutAlert
        if #available(macOS 15.4, *) {
            // 0 default (never asked), 1 ask, 2 always allow, 3 always deny.
            Self.logger.notice("Clipboard access behavior: \(pasteboard.accessBehavior.rawValue)")
        }
    }

    // MARK: - Actions

    /// Re-reads the access behavior (the user changes it in System Settings).
    internal func refresh() {
        let allowed = pasteboard.allowsReadingWithoutAlert
        if allowed != isAllowed {
            isAllowed = allowed
        }
    }

    /// Keeps ``isAllowed`` current while the app runs.
    internal func startRefreshing() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
            }
        }
    }

    /// Triggers the system alert once (until then macOS doesn't list Gloss), then opens Privacy & Security so the
    /// user can choose "Always Allow".
    internal func request() {
        if #available(macOS 15.4, *), pasteboard.accessBehavior == .default {
            // The read itself is what makes macOS ask; the contents are not used.
            _ = pasteboard.string(forType: .string)
        }
        refresh()
        guard !isAllowed, let url = Self.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - NSPasteboard

extension NSPasteboard {
    /// Whether reading this pasteboard never shows the paste privacy alert: "Always Allow" on macOS 15.4 and
    /// later, and always before that, since the alert didn't exist.
    internal var allowsReadingWithoutAlert: Bool {
        if #available(macOS 15.4, *) {
            return accessBehavior == .alwaysAllow
        }
        return true
    }
}
