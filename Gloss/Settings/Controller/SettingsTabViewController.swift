//
//  SettingsTabViewController.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/14.
//

import Foundation
import AppKit

/// The settings window's tabs, as toolbar buttons. Switching tabs fades the panes into each other while the window
/// grows or shrinks to the new pane's height, its top edge staying in place.
@MainActor
internal final class SettingsTabViewController: NSTabViewController {
    // MARK: - Lifecycle

    internal init() {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        transitionOptions = [.crossfade, .allowUserInteraction]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Actions

    internal func addPane(_ pane: SettingsPaneViewController, title: String, symbol: String) {
        // The tab view controller passes the selected tab's title on to the window.
        pane.title = title
        pane.onHeightChange = { [weak self, weak pane] in
            guard let self, let pane, self.selectedPane === pane else { return }
            self.fitWindow(animated: self.view.window?.isVisible == true)
        }
        let item = NSTabViewItem(viewController: pane)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        addTabViewItem(item)
    }

    /// Gives the window the selected pane's height, keeping its top edge where it is.
    internal func fitWindow(animated: Bool) {
        guard let window = view.window, let pane = selectedPane else { return }
        let content = window.contentRect(forFrameRect: window.frame)
        let height = pane.preferredHeight
        guard abs(content.height - height) >= 1 else { return }
        var frame = window.frameRect(forContentRect: NSRect(
            x: content.minX,
            y: content.minY,
            width: SettingsLayout.width,
            height: height
        ))
        frame.origin.y = window.frame.maxY - frame.height
        guard animated else {
            window.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = SettingsLayout.resizeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        }
    }

    // MARK: - NSTabViewDelegate

    override internal func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        fitWindow(animated: view.window?.isVisible == true)
    }

    // MARK: - Private

    private var selectedPane: SettingsPaneViewController? {
        guard tabViewItems.indices.contains(selectedTabViewItemIndex) else { return nil }
        return tabViewItems[selectedTabViewItemIndex].viewController as? SettingsPaneViewController
    }
}
