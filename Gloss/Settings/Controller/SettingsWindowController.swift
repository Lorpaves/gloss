//
//  SettingsWindowController.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import AppKit

/// The settings window: tabs in the toolbar, each a pane with a grouped form. The window takes the height of the pane
/// shown, animating between tabs.
@MainActor
internal final class SettingsWindowController: ForegroundWindowController {
    /// The tabs, in toolbar order.
    internal enum Tab: Int, CaseIterable {
        case general
        case apps
        case permissions
        case model
        case about
    }

    // MARK: - Props

    private let tabViewController: SettingsTabViewController
    private let noticesWindow: ThirdPartyNoticesWindowController

    // MARK: - Lifecycle

    internal init(
        settingsStore: SettingsStore,
        accessibility: AccessibilityPermission,
        clipboard: ClipboardPermission,
        loginItem: LoginItem,
        model: ModelManager,
        updater: AppUpdater
    ) {
        let tabs = SettingsTabViewController()
        tabs.addPane(
            SettingsPaneViewController(form: GeneralSettingsView(
                settingsStore: settingsStore,
                loginItem: loginItem,
                updater: updater
            )),
            title: String(localized: "通用"),
            symbol: "gearshape"
        )
        tabs.addPane(
            SettingsPaneViewController(form: ExcludedAppsSettingsView(settingsStore: settingsStore)),
            title: String(localized: "App"),
            symbol: "square.grid.2x2"
        )
        tabs.addPane(
            SettingsPaneViewController(form: PermissionSettingsView(
                settingsStore: settingsStore,
                accessibility: accessibility,
                clipboard: clipboard
            )),
            title: String(localized: "权限"),
            symbol: "hand.raised"
        )
        tabs.addPane(
            SettingsPaneViewController(form: ModelSettingsView(model: model, settingsStore: settingsStore)),
            title: String(localized: "模型"),
            symbol: "cpu"
        )
        let notices = ThirdPartyNoticesWindowController()
        tabs.addPane(
            SettingsPaneViewController(form: AboutSettingsView(info: AppInfo()) {
                notices.present()
            }),
            title: String(localized: "关于"),
            symbol: "info.circle"
        )
        tabViewController = tabs
        noticesWindow = notices

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        // Toolbar and title bar in one: the traffic lights sit well inside the corner, which the preference style's
        // separate title row crowds them into. The tabs take the middle of the toolbar instead of the title.
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden
        if let toolbar = window.toolbar {
            toolbar.centeredItemIdentifiers = Set(toolbar.items.map(\.itemIdentifier))
        }
        super.init(window: window)
        tabs.fitWindow(animated: false)
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Actions

    /// Shows the window, switched to `tab` if given (otherwise to the tab it showed last).
    internal func show(tab: Tab?) {
        if let tab {
            tabViewController.selectedTabViewItemIndex = tab.rawValue
        }
        show()
    }
}
