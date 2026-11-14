//
//  OnboardingWindowController.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/14.
//

import Foundation
import AppKit
import SwiftUI

/// The welcome guide's window. It comes back to the front by itself when the user grants a permission in System
/// Settings. Only finishing the guide marks it as done; closing the window early doesn't.
@MainActor
internal final class OnboardingWindowController: ForegroundWindowController {
    // MARK: - Properties

    private let onClose: () -> Void

    // MARK: - Lifecycle

    /// - Parameter onClose: Called when the window closes, whether finished or closed early.
    internal init(viewModel: OnboardingViewModel, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let window = NSWindow(contentViewController: OnboardingViewController(viewModel: viewModel))
        window.styleMask = [.titled, .closable]
        window.title = String(localized: "欢迎使用 Gloss")
        window.titleVisibility = .hidden
        // The title bar shows the window's background, so it blends into the pages below it.
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        // An empty toolbar gives the title bar of toolbar windows, where the traffic lights sit well inside the
        // corner.
        let toolbar = NSToolbar()
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        // Adding the toolbar changes the content size; set it once the title bar is final.
        window.setContentSize(OnboardingViewController.contentSize)
        super.init(window: window)
        window.center()
        viewModel.onFinish = { [weak self] in
            self?.close()
        }
        viewModel.onPermissionGranted = { [weak self] in
            self?.show()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - NSWindowDelegate

    override internal func windowWillClose(_ notification: Notification) {
        super.windowWillClose(notification)
        onClose()
    }
}
