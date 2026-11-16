//
//  PopupShadowView.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/16.
//

import Foundation
import AppKit

/// Holds the popup's glass and draws a soft shadow around it.
///
/// The window's own shadow can't be used: the window server rims it with a dark hairline, which reads as a black
/// border around dark glass over light content (a white page, Figma's canvas). This shadow is drawn only outside
/// the glass, so it doesn't show through it either.
internal final class PopupShadowView: NSView {
    // MARK: - Views

    private let shadowLayer = CALayer()
    /// Clips the shadow to what lies outside the glass.
    private let clipLayer = CALayer()
    private let clipShape = CAShapeLayer()

    // MARK: - Props

    /// Room left for the shadow on every side of the glass.
    internal static let margin: CGFloat = 24

    private let cornerRadius: CGFloat

    // MARK: - Lifecycle

    /// - Parameters:
    ///   - content: The glass.
    ///   - cornerRadius: Its corner radius, which the shadow follows.
    internal init(content: NSView, cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        commonInit(content: content)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override internal func layout() {
        super.layout()
        updateShadow()
    }

    /// Only the glass is the popup: a press on its shadow isn't one on the popup.
    override internal func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        return view === self ? nil : view
    }

    // MARK: - Private

    private func commonInit(content: NSView) {
        wantsLayer = true
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOpacity = 0.22
        shadowLayer.shadowRadius = 10
        // Light from above: the shadow falls a little below the popup.
        shadowLayer.shadowOffset = CGSize(width: 0, height: -3)
        clipShape.fillRule = .evenOdd
        clipLayer.mask = clipShape
        clipLayer.addSublayer(shadowLayer)
        layer?.addSublayer(clipLayer)

        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.margin),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.margin),
            content.topAnchor.constraint(equalTo: topAnchor, constant: Self.margin),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.margin)
        ])
    }

    private func updateShadow() {
        let glass = bounds.insetBy(dx: Self.margin, dy: Self.margin)
        // A rounded rect can't have corners larger than half of its sides.
        let radius = min(cornerRadius, glass.width / 2, glass.height / 2)
        CATransaction.begin()
        // Follows the popup as it resizes and glides, without animations of its own.
        CATransaction.setDisableActions(true)
        clipLayer.frame = bounds
        shadowLayer.frame = bounds
        clipShape.frame = bounds
        if radius > 0 {
            let outline = CGPath(roundedRect: glass, cornerWidth: radius, cornerHeight: radius, transform: nil)
            shadowLayer.shadowPath = outline
            let outside = CGMutablePath()
            outside.addRect(bounds)
            outside.addPath(outline)
            clipShape.path = outside
        } else {
            shadowLayer.shadowPath = nil
            clipShape.path = nil
        }
        CATransaction.commit()
    }
}
