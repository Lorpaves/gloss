//
//  ScreenGeometry.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import CoreGraphics

/// Coordinate conversions and checks between Quartz / Accessibility space (origin at the top-left of the primary
/// display, y down) and Cocoa space (origin at the bottom-left of the primary display, y up).
internal enum ScreenGeometry {
    // MARK: - Conversion

    /// Converts a rect between Quartz and Cocoa coordinates (the conversion is its own inverse).
    /// - Parameters:
    ///   - rect: Rect in one coordinate space.
    ///   - primaryScreenHeight: Height of `NSScreen.screens[0]`, the display with the menu bar.
    /// - Returns: The rect in the other space.
    internal static func flipped(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Converts a point between Quartz and Cocoa coordinates.
    internal static func flipped(_ point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    // MARK: - Checks

    /// Whether a selection rect reported by an app can anchor the popup.
    /// - Parameters:
    ///   - rect: Selection bounds (Cocoa coordinates).
    ///   - screenFrames: Frames of all screens (Cocoa coordinates).
    /// - Returns: `false` for empty, non-finite or off-screen rects and for rects taller than 60 % of their screen
    ///   (the pointer is a better anchor for those).
    internal static func isUsableAnchor(_ rect: CGRect, screenFrames: [CGRect]) -> Bool {
        guard isMeasurable(rect), let screen = screenFrames.first(where: { $0.intersects(rect) }) else { return false }
        return rect.height <= screen.height * 0.6
    }

    /// Whether a rect has finite coordinates and a non-zero size (apps sometimes report garbage bounds).
    internal static func isMeasurable(_ rect: CGRect) -> Bool {
        let values = [rect.origin.x, rect.origin.y, rect.width, rect.height]
        return values.allSatisfy(\.isFinite) && rect.width > 0 && rect.height > 0
    }

    /// Whether `point` lies within `distance` of `rect`.
    internal static func isPoint(_ point: CGPoint, near rect: CGRect, within distance: CGFloat) -> Bool {
        rect.insetBy(dx: -distance, dy: -distance).contains(point)
    }

    /// The frame among `frames` that contains `point`, or the closest one.
    internal static func frame(containing point: CGPoint, in frames: [CGRect]) -> CGRect? {
        if let match = frames.first(where: { $0.contains(point) }) {
            return match
        }
        return frames.min { distance(from: point, to: $0) < distance(from: point, to: $1) }
    }

    /// The frame among `frames` that shows the most of `rect`.
    /// - Returns: `nil` when none of them shows any of it.
    internal static func frame(showingMostOf rect: CGRect, in frames: [CGRect]) -> CGRect? {
        frames
            .map { (frame: $0, shown: area(of: $0.intersection(rect))) }
            .filter { $0.shown > 0 }
            .max { $0.shown < $1.shown }?
            .frame
    }

    /// The part of a selection that is in view: what is left of `rect` inside every frame that clips it (the
    /// scroll areas it sits in, its window).
    /// - Returns: `nil` when the selection is scrolled out of view.
    internal static func visiblePart(of rect: CGRect, clippedBy clipFrames: [CGRect]) -> CGRect? {
        let visible = clipFrames.reduce(rect) { $0.intersection($1) }
        return isMeasurable(visible) ? visible : nil
    }

    /// A rect spanning a press from `start` to `end`, standing in for selection bounds the app doesn't report: the
    /// popup then sits under the text the user dragged across rather than under the pointer.
    /// - Parameter lineHeight: Height given to each end of the press.
    internal static func pressAnchor(from start: CGPoint, to end: CGPoint, lineHeight: CGFloat = 20) -> CGRect {
        let half = lineHeight / 2
        return CGRect(x: start.x, y: start.y - half, width: 1, height: lineHeight)
            .union(CGRect(x: end.x, y: end.y - half, width: 1, height: lineHeight))
    }

    // MARK: - Windows

    /// Bounds of an on-screen window in Quartz coordinates. Reading bounds needs no Screen Recording permission.
    internal static func windowBounds(of windowID: CGWindowID) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let info = list.first,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary
        else { return nil }
        return CGRect(dictionaryRepresentation: bounds)
    }

    // MARK: - Private

    /// Area of a rect; nothing for the null rect two frames that don't meet intersect to.
    private static func area(of rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
