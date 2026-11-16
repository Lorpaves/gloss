//
//  ThirdPartyNoticesWindowController.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/16.
//

import Foundation
import AppKit

/// Shows the licenses of the software shipped inside Gloss.
///
/// A window of its own rather than a sheet on Settings: an app can't quit while one of its windows has a sheet
/// up, which would also hold back logging out and installing an update.
@MainActor
internal final class ThirdPartyNoticesWindowController: ForegroundWindowController {
    // MARK: - Views

    private let textView: NSTextView

    // MARK: - Props

    private var isLoaded = false

    private static let contentSize = NSSize(width: 600, height: 460)
    private static let textInset = NSSize(width: 16, height: 16)

    // MARK: - Lifecycle

    internal init() {
        let scrollView = NSTextView.scrollableTextView()
        // The factory always puts a text view in.
        textView = scrollView.documentView as? NSTextView ?? NSTextView()
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: true
        )
        window.title = String(localized: "第三方许可")
        window.contentView = scrollView
        window.contentMinSize = NSSize(width: 420, height: 240)
        super.init(window: window)
        commonInit()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Actions

    /// Shows the window, reading the notices the first time.
    internal func present() {
        if !isLoaded {
            isLoaded = true
            textView.string = AppInfo.thirdPartyNotices()
            window?.center()
        }
        show()
    }

    // MARK: - Private

    private func commonInit() {
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = Self.textInset
    }
}
