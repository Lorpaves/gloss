//
//  CapturedSelection.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import CoreGraphics

/// Text the user selected in another app.
internal struct CapturedSelection: Equatable, Sendable {
    /// How the text was obtained.
    internal enum Source: Sendable {
        case accessibility
        case copy
    }

    internal var text: String
    internal var processID: pid_t
    /// Selection bounds in Quartz coordinates, when the app reports them.
    internal var bounds: CGRect?
    /// Frames of the scroll areas (or the window) that clip the selection, in Quartz coordinates.
    internal var clipFrames: [CGRect] = []
    internal var source: Source
}
