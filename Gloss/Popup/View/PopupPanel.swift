//
//  PopupPanel.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import AppKit

/// Borderless floating panel that never takes keyboard focus from the app the user is reading in.
internal final class PopupPanel: NSPanel {
    // MARK: - Lifecycle

    internal init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        // Gloss is never the active app, so the default (true) would hide the panel immediately.
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Focus

    override internal var canBecomeKey: Bool {
        false
    }

    override internal var canBecomeMain: Bool {
        false
    }
}
