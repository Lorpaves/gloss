//
//  ProgressRing.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/14.
//

import SwiftUI

/// A ring that fills clockwise from the top: the model download's progress in Settings and the welcome guide.
///
/// The system's determinate circular progress view draws as a heavy gray pie on macOS; this is a thin ring in the
/// accent color, by default as big as the circle symbols next to it.
internal struct ProgressRing: View {
    // MARK: - Properties

    /// From 0 to 1.
    internal let fraction: Double
    /// Outer size.
    internal var diameter: CGFloat = 14
    internal var lineWidth: CGFloat = 2

    // MARK: - Body

    internal var body: some View {
        // Inset by half the line, so the stroke stays inside the circle's frame.
        let circle = Circle().inset(by: lineWidth / 2)
        ZStack {
            circle
                .stroke(.quaternary, lineWidth: lineWidth)
            circle
                .trim(from: 0, to: fraction)
                .stroke(.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
        .animation(.linear(duration: 0.2), value: fraction)
        // The text next to it says how far along it is.
        .accessibilityHidden(true)
    }
}
