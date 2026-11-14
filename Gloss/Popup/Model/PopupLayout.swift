//
//  PopupLayout.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import CoreGraphics

/// Where the popup sits relative to the selection: below it by default, above it when there's no room below.
///
/// The popup sizes itself to its content up to ``maximumWidth`` × ``maxHeight``. Its leading edge and the edge
/// facing the selection stay put while it grows, so streaming text extends it to the right and away from the
/// selection.
internal struct PopupLayout: Equatable, Sendable {
    internal enum Placement: Equatable, Sendable {
        case below
        case above
    }

    // MARK: - Properties

    internal var placement: Placement
    /// The edge that stays put while the popup grows: its top edge below the selection, its bottom edge above it.
    internal var anchoredEdgeY: CGFloat
    /// Preferred left edge; the popup only shifts left of it to stay on screen.
    internal var leadingX: CGFloat
    /// Tallest the popup may get at this position.
    internal var maxHeight: CGFloat
    internal var visibleFrame: CGRect

    internal static let maximumWidth: CGFloat = 420
    internal static let maximumHeight: CGFloat = 420
    /// Distance from the popup's left edge to its text, so the translation lines up under the selection.
    internal static let contentInset: CGFloat = 18
    internal static let gap: CGFloat = 6
    internal static let margin: CGFloat = 8
    /// Below is preferred as long as at least this much room is left there.
    private static let preferredRoomBelow: CGFloat = 160
    private static let minimumHeight: CGFloat = 40

    // MARK: - Layout

    /// Places the popup for a selection; decided once per selection.
    /// - Parameters:
    ///   - anchor: Selection bounds, or a small rect around the pointer (Cocoa coordinates).
    ///   - leadingX: Preferred left edge of the popup.
    ///   - visibleFrame: Visible frame of the screen with the selection.
    /// - Returns: The layout.
    internal static func make(anchor: CGRect, leadingX: CGFloat, visibleFrame: CGRect) -> PopupLayout {
        let roomBelow = (anchor.minY - gap) - (visibleFrame.minY + margin)
        let roomAbove = (visibleFrame.maxY - margin) - (anchor.maxY + gap)
        let fitsBelow = roomBelow >= min(maximumHeight, preferredRoomBelow) || roomBelow >= roomAbove
        let placement: Placement = fitsBelow ? .below : .above
        let room = placement == .below ? roomBelow : roomAbove
        return PopupLayout(
            placement: placement,
            anchoredEdgeY: placement == .below ? anchor.minY - gap : anchor.maxY + gap,
            leadingX: leadingX,
            maxHeight: min(maximumHeight, max(room, minimumHeight)),
            visibleFrame: visibleFrame
        )
    }

    /// The popup's frame for content of `size`: capped at ``maximumWidth`` × ``maxHeight``, with the leading and
    /// anchored edges in place, and kept on screen.
    internal func frame(for size: CGSize) -> CGRect {
        let width = min(max(size.width, 1), Self.maximumWidth, visibleFrame.width - 2 * Self.margin)
        let height = min(max(size.height, 1), maxHeight)
        let minX = visibleFrame.minX + Self.margin
        let maxX = max(minX, visibleFrame.maxX - Self.margin - width)
        let preferredY = placement == .below ? anchoredEdgeY - height : anchoredEdgeY
        let lowestY = visibleFrame.minY + Self.margin
        let highestY = max(lowestY, visibleFrame.maxY - Self.margin - height)
        return CGRect(
            x: min(max(leadingX, minX), maxX),
            y: min(max(preferredY, lowestY), highestY),
            width: width,
            height: height
        )
    }

    /// Re-anchors the layout where the user dragged the popup.
    internal mutating func move(to frame: CGRect) {
        leadingX = frame.minX
        anchoredEdgeY = placement == .below ? frame.maxY : frame.minY
    }
}
