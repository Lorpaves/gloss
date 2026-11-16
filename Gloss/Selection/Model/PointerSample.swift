//
//  PointerSample.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import CoreGraphics

/// Modifier keys held during a mouse event.
internal struct PointerModifiers: OptionSet, Hashable, Sendable {
    internal let rawValue: Int

    internal init(rawValue: Int) {
        self.rawValue = rawValue
    }

    internal static let shift = PointerModifiers(rawValue: 1 << 0)
    internal static let control = PointerModifiers(rawValue: 1 << 1)
    internal static let option = PointerModifiers(rawValue: 1 << 2)
    internal static let command = PointerModifiers(rawValue: 1 << 3)
}

/// A Sendable snapshot of one global mouse event.
internal struct PointerSample: Equatable, Sendable {
    /// Location in Quartz / Accessibility coordinates (origin at the top-left of the primary display).
    internal var quartzLocation: CGPoint
    /// Location in Cocoa screen coordinates (origin at the bottom-left of the primary display).
    internal var cocoaLocation: CGPoint
    internal var clickCount: Int
    internal var modifiers: PointerModifiers
}

/// State recorded when the left button went down, compared again at mouse-up.
internal struct PointerDownContext: Equatable, Sendable {
    internal var sample: PointerSample
    /// The window under the pointer, if any.
    internal var windowID: CGWindowID?
    /// That window's bounds (Quartz coordinates).
    internal var windowBounds: CGRect?
    /// Change count of the drag pasteboard; it changes when a drag-and-drop session starts.
    internal var dragPasteboardChangeCount: Int
}

/// State recorded when the left button went up.
internal struct PointerUpContext: Equatable, Sendable {
    internal var sample: PointerSample
    /// Current bounds of the window that was under the pointer at mouse-down; `nil` if it closed.
    internal var windowBounds: CGRect?
    internal var dragPasteboardChangeCount: Int
}

/// What ``SelectionEventMonitor`` reports.
internal enum SelectionSignal: Sendable {
    /// Any button went down outside Gloss's windows.
    case pointerDown(PointerSample)
    /// The left button went up after a press that started outside Gloss's windows.
    case pointerUp(down: PointerDownContext, up: PointerUpContext)
    /// The user scrolled with the pointer at this location (Cocoa coordinates), outside Gloss's windows. Only
    /// reported while ``SelectionEventMonitor/reportsScrolling``.
    case scroll(at: CGPoint)
    /// The user selected text with the keyboard in another app.
    case keyboardSelection(SelectionKey)
}
