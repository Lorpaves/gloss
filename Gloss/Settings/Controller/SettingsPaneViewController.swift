//
//  SettingsPaneViewController.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/14.
//

import Foundation
import AppKit
import SwiftUI

/// A tab of the settings window: a SwiftUI form at its natural height, pinned to the top.
///
/// The forms are SwiftUI because the system's grouped `Form` has no AppKit counterpart. The window is AppKit's: the
/// pane only reports how tall its form is, and ``SettingsTabViewController`` animates the window to that height.
/// (A hosting controller that sizes the window itself makes it jump.)
@MainActor
internal final class SettingsPaneViewController: NSViewController {
    // MARK: - Views

    private let formView: NSView

    // MARK: - Props

    /// Called when ``preferredHeight`` changes after the pane was first laid out.
    internal var onHeightChange: () -> Void = {}
    private var reportedHeight: CGFloat?

    /// Height of the form, which the window takes while this tab is selected.
    internal var preferredHeight: CGFloat {
        loadViewIfNeeded()
        return formView.fittingSize.height.rounded(.up)
    }

    // MARK: - Lifecycle

    internal init(form: some View) {
        formView = NSHostingView(
            rootView: form
                .frame(width: SettingsLayout.width)
                .fixedSize(horizontal: false, vertical: true)
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override internal func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: SettingsLayout.width, height: 200))
    }

    override internal func viewDidLoad() {
        super.viewDidLoad()
        commonInit()
    }

    override internal func viewDidLayout() {
        super.viewDidLayout()
        // The form changed its height: a row appeared, or grew a second line.
        reportHeightIfChanged()
    }

    // MARK: - Private

    private func commonInit() {
        addSubviews()
    }

    private func addSubviews() {
        formView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(formView)
        // Pinned to the top only: while the window grows or shrinks, the form stays where it is.
        NSLayoutConstraint.activate([
            formView.topAnchor.constraint(equalTo: view.topAnchor),
            formView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            formView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    /// The first height isn't reported: the tab view controller asks for it when it shows the pane.
    private func reportHeightIfChanged() {
        let height = preferredHeight
        defer { reportedHeight = height }
        guard let reportedHeight, reportedHeight != height else { return }
        onHeightChange()
    }
}
