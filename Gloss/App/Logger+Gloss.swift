//
//  Logger+Gloss.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import os

extension Logger {
    /// A logger in the app's subsystem.
    ///
    /// Watch the whole pipeline with `log stream --level debug --predicate 'subsystem == "com.lorpaves.Gloss"'`.
    /// - Parameter category: Component name, e.g. `"AccessibilityReader"`.
    /// - Returns: The logger.
    internal static func gloss(_ category: String) -> Logger {
        Logger(subsystem: "com.lorpaves.Gloss", category: category)
    }
}
