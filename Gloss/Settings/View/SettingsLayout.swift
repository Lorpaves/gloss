//
//  SettingsLayout.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/14.
//

import Foundation

/// Measurements shared by the settings tabs.
internal enum SettingsLayout {
    /// Every tab has this width, so the window only changes height between tabs.
    internal static let width: CGFloat = 480
    /// Tallest the list of excluded apps gets before it scrolls.
    internal static let maximumListHeight: CGFloat = 460
    /// How long the window takes to change its height between tabs.
    internal static let resizeDuration: TimeInterval = 0.25
}
