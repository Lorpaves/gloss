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

    /// Whether the frames an app reports for the scroll areas around a selection can be right: each of them has to
    /// show, at least in part, inside the window they belong to.
    ///
    /// A web view whose page was never told where its window is reports everything as if that window sat in a
    /// corner of the main display (seen with Safari 27): text, bounds and scroll area are then all off by the
    /// same distance, and only the window's own frame gives it away.
    internal static func areFrames(_ frames: [CGRect], insideWindowWithFrame windowFrame: CGRect) -> Bool {
        frames.allSatisfy { $0.intersects(windowFrame) }
    }

    /// How far from where it is a web view that lost track of its window reports everything on its page.
    ///
    /// The page's own scroll area fills the view that holds it, except for what covers the top of that view
    /// (Safari's toolbar), so in place the two share their left and bottom edges. The view is reported by the app
    /// itself and is where it says.
    /// - Parameters:
    ///   - scrollAreaFrame: The frame the page reports for its scroll area (Quartz coordinates).
    ///   - viewFrame: The frame of the view that holds it (Quartz coordinates).
    /// - Returns: The distance from where things are to where the page reports them, or `nil` when the scroll
    ///   area doesn't fit into the view, which then isn't what holds it.
    internal static func misplacement(
        ofScrollAreaWithFrame scrollAreaFrame: CGRect,
        inViewWithFrame viewFrame: CGRect
    ) -> CGVector? {
        let tolerance: CGFloat = 1
        guard scrollAreaFrame.width <= viewFrame.width + tolerance,
              scrollAreaFrame.height <= viewFrame.height + tolerance
        else { return nil }
        return CGVector(dx: scrollAreaFrame.minX - viewFrame.minX, dy: scrollAreaFrame.maxY - viewFrame.maxY)
    }

    /// A rect spanning a press from `start` to `end`, standing in for selection bounds the app doesn't report: the
    /// popup then sits under the text the user dragged across rather than under the pointer.
    /// - Parameter lineHeight: Height given to each end of the press.
    internal static func pressAnchor(from start: CGPoint, to end: CGPoint, lineHeight: CGFloat = 20) -> CGRect {
        let half = lineHeight / 2
        return CGRect(x: start.x, y: start.y - half, width: 1, height: lineHeight)
            .union(CGRect(x: end.x, y: end.y - half, width: 1, height: lineHeight))
    }

    /// Where the popup goes for a selection made with the keyboard that the app doesn't locate: at the pointer
    /// while that is over the window the selection is in, otherwise in the middle of that window.
    /// - Parameters:
    ///   - pointer: Pointer location (Cocoa coordinates).
    ///   - windowFrame: Frame of the window with the selection, if known (Cocoa coordinates).
    ///   - lineHeight: Height given to the anchor.
    internal static func keyboardAnchor(pointer: CGPoint, windowFrame: CGRect?, lineHeight: CGFloat = 20) -> CGRect {
        var point = pointer
        if let windowFrame, !windowFrame.contains(pointer) {
            point = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        }
        return pressAnchor(from: point, to: point, lineHeight: lineHeight)
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

    /// The process that owns an on-screen window.
    internal static func ownerProcessID(of windowID: CGWindowID) -> pid_t? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let processID = list.first?[kCGWindowOwnerPID as String] as? Int32
        else { return nil }
        return processID
    }

    /// Bounds of the frontmost ordinary window of a process (Quartz coordinates).
    internal static func frontWindowBounds(ofProcess processID: pid_t) -> CGRect? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        // The list is ordered front to back; layer 0 leaves out menus, panels above other apps and the like.
        let window = list.first { info in
            info[kCGWindowOwnerPID as String] as? Int32 == processID && info[kCGWindowLayer as String] as? Int == 0
        }
        return (window?[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) }
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
