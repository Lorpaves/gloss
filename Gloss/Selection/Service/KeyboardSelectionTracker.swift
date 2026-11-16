//
//  KeyboardSelectionTracker.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/16.
//

import Foundation

/// Tells when a selection made with the keyboard is ready to be read.
///
/// ⌘A selects everything at once. Shift with the arrow keys selects step by step, and a held key repeats, so that
/// selection is only read once Shift is let go, the way a drag is read when the button comes up.
internal struct KeyboardSelectionTracker: Sendable {
    // MARK: - Properties

    /// Shift is down and has extended the selection.
    private var isExtending = false

    // MARK: - Actions

    /// Takes a key press.
    /// - Parameters:
    ///   - keyCode: The key's virtual key code.
    ///   - characters: What the key types in the current keyboard layout, modifiers aside.
    ///   - modifiers: Modifier keys held.
    ///   - isRepeat: Whether the press comes from holding the key.
    /// - Returns: The selection to read now, if this press completed one.
    internal mutating func keyDown(
        keyCode: UInt16,
        characters: String?,
        modifiers: PointerModifiers,
        isRepeat: Bool
    ) -> SelectionKey? {
        switch SelectionKey.classify(keyCode: keyCode, characters: characters, modifiers: modifiers) {
        case .selectAll:
            isExtending = false
            return isRepeat ? nil : .selectAll
        case .extend:
            isExtending = true
            return nil
        case nil:
            // Typing replaces what Shift selected.
            isExtending = false
            return nil
        }
    }

    /// Takes a change of the modifier keys held.
    /// - Returns: The selection to read now, if letting Shift go completed one.
    internal mutating func modifiersChanged(to modifiers: PointerModifiers) -> SelectionKey? {
        guard isExtending, !modifiers.contains(.shift) else { return nil }
        isExtending = false
        return .extend
    }
}
