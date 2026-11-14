//
//  SelectionGesture.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import CoreGraphics

/// A press that probably selected text.
internal enum SelectionGesture: Equatable, Sendable {
    /// The pointer moved while the button was down.
    case drag
    /// Double-click (word) or triple-click (line / paragraph).
    case multiClick(Int)
    /// Shift-click, which extends an existing selection.
    case shiftClick

    // MARK: - Properties

    /// Movement below this is a plain click.
    internal static let minimumDragDistance: CGFloat = 6
    /// Window bounds may differ by rounding noise without the window having moved.
    private static let windowTolerance: CGFloat = 0.5

    /// How long to wait for the app to finish updating its selection before reading it.
    internal var settleDelay: Duration {
        switch self {
        case .multiClick(2):
            // Long enough for a following third click to replace the double-click.
            .milliseconds(220)
        case .drag, .multiClick, .shiftClick:
            .milliseconds(120)
        }
    }

    /// Whether the copy fallback may run for this gesture (a shift-click in a list would copy whole rows).
    internal var allowsCopyFallback: Bool {
        self != .shiftClick
    }

    // MARK: - Classification

    /// Why a press doesn't count as a selection; logged to explain missing popups.
    internal enum Rejection: String, Sendable {
        case plainClick = "plain click"
        case modifier = "⌘ or ⌃ held"
        case dragAndDrop = "drag and drop"
        case windowChanged = "window moved, resized or closed"
    }

    /// Decides whether a press selected text.
    /// - Parameters:
    ///   - down: State at mouse-down.
    ///   - up: State at mouse-up.
    /// - Returns: The gesture, or `nil` for plain clicks, window moves and resizes, drag-and-drop and
    ///   ⌘ / ⌃ clicks (see ``rejection(down:up:)``).
    internal static func classify(down: PointerDownContext, up: PointerUpContext) -> SelectionGesture? {
        guard rejection(down: down, up: up) == nil else { return nil }
        if distance(down, up) >= minimumDragDistance {
            return .drag
        }
        if up.sample.clickCount >= 2 {
            return .multiClick(up.sample.clickCount)
        }
        return .shiftClick
    }

    /// Why a press isn't a selection, or `nil` when it is one.
    internal static func rejection(down: PointerDownContext, up: PointerUpContext) -> Rejection? {
        let modifiers = down.sample.modifiers.union(up.sample.modifiers)
        guard modifiers.isDisjoint(with: [.command, .control]) else { return .modifier }
        guard up.dragPasteboardChangeCount == down.dragPasteboardChangeCount else { return .dragAndDrop }
        if let before = down.windowBounds {
            guard let after = up.windowBounds, isSame(before, after) else { return .windowChanged }
        }
        let isSelection = distance(down, up) >= minimumDragDistance
            || up.sample.clickCount >= 2
            || modifiers.contains(.shift)
        return isSelection ? nil : .plainClick
    }

    // MARK: - Private

    private static func distance(_ down: PointerDownContext, _ up: PointerUpContext) -> CGFloat {
        let dx = up.sample.cocoaLocation.x - down.sample.cocoaLocation.x
        let dy = up.sample.cocoaLocation.y - down.sample.cocoaLocation.y
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func isSame(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= windowTolerance
            && abs(lhs.minY - rhs.minY) <= windowTolerance
            && abs(lhs.width - rhs.width) <= windowTolerance
            && abs(lhs.height - rhs.height) <= windowTolerance
    }
}
