//
//  SelectionKey.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/16.
//

import Foundation

/// A key press that selects text.
internal enum SelectionKey: Equatable, Sendable {
    /// ⌘A.
    case selectAll
    /// Shift with an arrow key, Home, End, Page Up or Page Down, alone or with ⌥ or ⌘, which extends the selection.
    case extend

    // MARK: - Properties

    /// How long to wait for the app to finish updating its selection before reading it.
    internal var settleDelay: Duration {
        switch self {
        case .selectAll:
            // Selecting a whole document takes some apps a moment.
            .milliseconds(200)
        case .extend:
            .milliseconds(120)
        }
    }

    /// Arrow keys, Home, End, Page Up and Page Down. Unlike letters, these sit on the same keys in every layout.
    private static let navigationKeyCodes: Set<UInt16> = [123, 124, 125, 126, 115, 119, 116, 121]

    // MARK: - Classification

    /// Decides whether a key press selects text.
    /// - Parameters:
    ///   - keyCode: The key's virtual key code.
    ///   - characters: What the key types in the current keyboard layout, modifiers aside.
    ///   - modifiers: Modifier keys held.
    /// - Returns: The kind of selection, or `nil` for every other key.
    internal static func classify(keyCode: UInt16, characters: String?, modifiers: PointerModifiers) -> SelectionKey? {
        if modifiers == .command, characters?.caseInsensitiveCompare("a") == .orderedSame {
            return .selectAll
        }
        // ⌃ with the arrow keys switches Spaces and windows.
        if modifiers.contains(.shift), !modifiers.contains(.control), navigationKeyCodes.contains(keyCode) {
            return .extend
        }
        return nil
    }
}
