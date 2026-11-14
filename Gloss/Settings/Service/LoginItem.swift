//
//  LoginItem.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import Observation
import ServiceManagement
import os

/// Whether Gloss opens when the user logs in. The system keeps the setting and also lists Gloss under Login Items
/// in System Settings, where the user can turn it off as well.
@MainActor
@Observable
internal final class LoginItem {
    // MARK: - Properties

    /// Whether Gloss opens at login.
    internal private(set) var isEnabled: Bool

    @ObservationIgnored private let service: SMAppService

    private static let logger = Logger.gloss("LoginItem")

    // MARK: - Lifecycle

    internal init(service: SMAppService = .mainApp) {
        self.service = service
        isEnabled = service.status == .enabled
    }

    // MARK: - Actions

    /// Re-reads the setting (the user changes it in System Settings too).
    internal func refresh() {
        let enabled = service.status == .enabled
        if enabled != isEnabled {
            isEnabled = enabled
        }
    }

    /// Makes Gloss open at login, or stops it from doing so.
    internal func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            Self.logger.error("Couldn't change the login item: \(error.localizedDescription, privacy: .public)")
        }
        // The user turned Gloss off under Login Items; only they can turn it back on there.
        if enabled, service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        refresh()
    }
}
