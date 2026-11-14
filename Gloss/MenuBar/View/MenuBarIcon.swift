//
//  MenuBarIcon.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import AppKit

/// The menu bar glyph: the app icon's selection capsule and I-beam cursor, as a monochrome template image so it
/// takes the menu bar's tint in every appearance.
@MainActor
internal enum MenuBarIcon {
    /// 20 × 13 pt, drawn once.
    internal static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 20, height: 13), flipped: true) { _ in
            NSColor.black.set()
            // Selection capsule, outlined like the translucent one in the app icon.
            let capsule = NSBezierPath(
                roundedRect: NSRect(x: 0.75, y: 3.75, width: 10.5, height: 5.5),
                xRadius: 2.75,
                yRadius: 2.75
            )
            capsule.lineWidth = 1.5
            capsule.stroke()
            // I-beam cursor: stem and two serifs.
            NSBezierPath(roundedRect: NSRect(x: 16, y: 1, width: 2, height: 11), xRadius: 1, yRadius: 1).fill()
            NSBezierPath(roundedRect: NSRect(x: 14, y: 0, width: 6, height: 2), xRadius: 1, yRadius: 1).fill()
            NSBezierPath(roundedRect: NSRect(x: 14, y: 11, width: 6, height: 2), xRadius: 1, yRadius: 1).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Gloss"
        return image
    }()
}
