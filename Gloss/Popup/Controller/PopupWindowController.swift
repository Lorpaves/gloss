//
//  PopupWindowController.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import AppKit
import SwiftUI

/// Shows the translation popup next to a selection, sizes it to its content, moves it with the selection and
/// decides when it goes away.
@MainActor
internal final class PopupWindowController {
    // MARK: - Properties

    internal let model: PopupViewModel

    /// Whether the popup is showing a selection. It may be hidden for the moment while that selection is
    /// scrolled out of view.
    internal private(set) var isPresented = false
    /// Whether the popup moves with its selection; ends when the user pins or drags it.
    internal private(set) var isFollowingSelection = false

    private let settingsStore: SettingsStore
    private let panel = PopupPanel()
    private let escapeInterceptor = EscapeKeyInterceptor()
    private var layout: PopupLayout?
    /// Last size the content reported, and the selection (the model's `generation`) it reported it for.
    private var contentSize: CGSize = .zero
    private var contentGeneration = 0
    /// Set while Gloss moves the panel itself, so that only the user's drags re-anchor the layout.
    private var isPositioning = false
    /// How far the panel reaches beyond the popup on every side, for the popup's shadow.
    private var shadowMargin: CGFloat = 0
    /// The selection is scrolled out of view; the popup comes back when it does.
    private var isHiddenWhileScrolledAway = false
    /// How far the popup was from its new place when the current glide started; nothing is left of it at the end.
    private var glideOffset = CGVector.zero
    private var glideStart = ContinuousClock.now
    private var glideDuration = Duration.zero
    private var glideTask: Task<Void, Never>?
    /// When the selection last moved, and the typical time between two of its moves while it keeps moving;
    /// nothing until the app has shown how often it reports them.
    private var lastFollowUpdate: ContinuousClock.Instant?
    private var followUpdateInterval = Duration.zero
    private var escapeTask: Task<Void, Never>?
    private var moveObserver: NSObjectProtocol?

    /// Size of the waiting state (spinner and buttons), used until the new content reports its own size.
    private static let placeholderSize = CGSize(width: 98, height: 45)
    /// Longest glide to a new position.
    private static let maximumGlide = Duration.milliseconds(100)
    /// Position updates closer together than this already look continuous, so the popup moves straight there.
    private static let minimumGlide = Duration.milliseconds(24)
    /// Position updates farther apart than this belong to two separate movements.
    private static let longestUpdateGap = Duration.milliseconds(150)
    private static let glideFrameInterval = Duration.milliseconds(8)

    // MARK: - Lifecycle

    /// - Parameters:
    ///   - model: State of the popup.
    ///   - settingsStore: Where the translation's font size comes from.
    internal init(model: PopupViewModel, settingsStore: SettingsStore) {
        self.model = model
        self.settingsStore = settingsStore
        installContent()
        escapeTask = Task { [weak self, escapeInterceptor] in
            for await _ in escapeInterceptor.presses {
                self?.dismiss()
            }
        }
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.panelDidMove()
            }
        }
    }

    // MARK: - Showing

    /// Shows the popup for a new selection; a pinned popup keeps its position.
    /// - Parameters:
    ///   - anchor: Selection bounds, or the span of the press (Cocoa coordinates).
    ///   - leadingX: Preferred left edge of the popup.
    ///   - followsSelection: Whether `anchor` is a real selection the popup can keep following.
    internal func present(anchor: CGRect, leadingX: CGFloat, followsSelection: Bool) {
        if !(model.isPinned && isPresented) {
            let screenFrames = NSScreen.screens.map(\.frame)
            let screenFrame = ScreenGeometry.frame(showingMostOf: anchor, in: screenFrames)
                ?? ScreenGeometry.frame(containing: CGPoint(x: anchor.midX, y: anchor.minY), in: screenFrames)
                ?? NSScreen.main?.frame
            guard let layout = makeLayout(anchor: anchor, leadingX: leadingX, onScreenWithFrame: screenFrame) else {
                return
            }
            self.layout = layout
            model.maxHeight = layout.maxHeight
            stopGlide()
            lastFollowUpdate = nil
            followUpdateInterval = .zero
            // The previous selection's size would flash first; start from the waiting state's size instead.
            applyFrame(layout.frame(for: Self.placeholderSize))
            isFollowingSelection = followsSelection
        }
        let wasPresented = isPresented
        isPresented = true
        isHiddenWhileScrolledAway = false
        // Resizing the panel above lays the content out, which can make it report its size before the popup
        // counts as presented. Content that then stays as it is never reports another one.
        if !wasPresented, contentGeneration == model.generation, let layout {
            applyFrame(layout.frame(for: contentSize))
        }
        panel.orderFrontRegardless()
        updateEscapeInterception()
    }

    /// Moves the popup with the part of its selection that is in view, hiding it while none of it is.
    ///
    /// The popup never leaves the selection's scroll area or screen for another: a selection scrolled past the top
    /// of its screen would otherwise drag the popup to whichever display is nearest.
    /// - Parameters:
    ///   - selectionBounds: Current selection bounds (Cocoa coordinates).
    ///   - clipFrames: Frames of the scroll areas or window that clip the selection, as far as known.
    internal func follow(selectionBounds: CGRect, clipFrames: [CGRect]) {
        guard isPresented, isFollowingSelection else { return }
        guard let visible = ScreenGeometry.visiblePart(of: selectionBounds, clippedBy: clipFrames),
              let layout = makeLayout(
                  anchor: visible,
                  leadingX: visible.minX - PopupLayout.contentInset,
                  onScreenWithFrame: ScreenGeometry.frame(showingMostOf: visible, in: NSScreen.screens.map(\.frame))
              )
        else {
            if !isHiddenWhileScrolledAway {
                isHiddenWhileScrolledAway = true
                stopGlide()
                panel.orderOut(nil)
                updateEscapeInterception()
            }
            return
        }
        if layout != self.layout {
            self.layout = layout
            model.maxHeight = layout.maxHeight
            if isHiddenWhileScrolledAway {
                applyFrame(layout.frame(for: displayedSize))
            } else {
                glide(to: layout)
            }
        }
        if isHiddenWhileScrolledAway {
            isHiddenWhileScrolledAway = false
            panel.orderFrontRegardless()
            updateEscapeInterception()
        }
    }

    // MARK: - Dismissal

    /// Hides the popup and stops its translation.
    internal func dismiss() {
        model.cancel()
        model.isPinned = false
        stopGlide()
        isPresented = false
        isFollowingSelection = false
        isHiddenWhileScrolledAway = false
        updateEscapeInterception()
        panel.orderOut(nil)
    }

    /// Hides the popup unless it is pinned (outside clicks, app and Space switches, a changed selection).
    internal func dismissUnlessPinned() {
        guard isPresented, !model.isPinned else { return }
        dismiss()
    }

    // MARK: - Private

    private func installContent() {
        let content = PopupContentView(
            model: model,
            settingsStore: settingsStore,
            onTogglePin: { [weak self] in
                self?.togglePin()
            },
            onClose: { [weak self] in
                self?.dismiss()
            },
            onSizeChange: { [weak self] size, generation in
                self?.contentSizeDidChange(size, generation: generation)
            }
        )
        let hostingView = PopupHostingView(rootView: content)
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let surface: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 16
            glass.contentView = hostingView
            surface = glass
            // The glass gets a shadow drawn around it instead of the window's (see ``PopupShadowView``), so the
            // panel is larger than the popup by the room that shadow takes.
            panel.hasShadow = false
            panel.contentView = PopupShadowView(content: glass, cornerRadius: glass.cornerRadius)
            shadowMargin = PopupShadowView.margin
        } else {
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = 12
            effect.layer?.masksToBounds = true
            effect.addSubview(hostingView)
            surface = effect
            panel.contentView = effect
        }
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: surface.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: surface.bottomAnchor)
        ])
    }

    /// Lays the popup out next to `anchor` on the screen with the frame `screenFrame`.
    private func makeLayout(anchor: CGRect, leadingX: CGFloat, onScreenWithFrame screenFrame: CGRect?) -> PopupLayout? {
        guard let screen = NSScreen.screens.first(where: { $0.frame == screenFrame }) else { return nil }
        return PopupLayout.make(anchor: anchor, leadingX: leadingX, visibleFrame: screen.visibleFrame)
    }

    /// A pinned popup stays where it is: it no longer follows its selection.
    private func togglePin() {
        model.isPinned.toggle()
        if model.isPinned {
            isFollowingSelection = false
        }
        updateEscapeInterception()
    }

    /// Esc closes an unpinned popup on screen; a pinned or scrolled-away one lets Esc through to the app.
    private func updateEscapeInterception() {
        let shouldIntercept = isPresented && !isHiddenWhileScrolledAway && !model.isPinned
        escapeInterceptor.isArmed = shouldIntercept
        if shouldIntercept {
            escapeInterceptor.start()
        } else {
            escapeInterceptor.stop()
        }
    }

    private func contentSizeDidChange(_ size: CGSize, generation: Int) {
        contentSize = size
        contentGeneration = generation
        guard let layout, isPresented else { return }
        applyFrame(glided(layout.frame(for: size)))
    }

    /// Where the popup is on screen: the panel without the room for its shadow.
    private var popupFrame: CGRect {
        panel.frame.insetBy(dx: shadowMargin, dy: shadowMargin)
    }

    /// Puts the popup at `target`, and the panel around it.
    private func applyFrame(_ target: CGRect) {
        let frame = target.insetBy(dx: -shadowMargin, dy: -shadowMargin)
        guard frame != panel.frame else { return }
        isPositioning = true
        if frame.size == panel.frame.size {
            panel.setFrameOrigin(frame.origin)
        } else {
            panel.setFrame(frame, display: true)
        }
        isPositioning = false
    }

    /// The user dragged the popup: keep it where they put it.
    private func panelDidMove() {
        guard !isPositioning else { return }
        stopGlide()
        layout?.move(to: popupFrame)
        isFollowingSelection = false
    }

    // MARK: - Private: gliding

    /// Size the popup shows at: the content's, or the waiting state's until the content has reported one.
    private var displayedSize: CGSize {
        contentSize == .zero ? Self.placeholderSize : contentSize
    }

    /// Part of the current glide that is still ahead: 1 at its start, 0 once the popup has arrived.
    private var glideRemaining: Double {
        guard glideDuration > .zero else { return 0 }
        return max(0, 1 - (ContinuousClock.now - glideStart) / glideDuration)
    }

    /// Moves the popup to where `layout` puts it, filling the time until the next position update with motion.
    ///
    /// Apps that report a scrolling selection continuously (TextEdit, Safari, Xcode) move the popup directly. Chrome
    /// only reports it about 12 times a second, which would look like jumping, so the popup glides from one
    /// reported position to the next over the typical time between two reports.
    ///
    /// That time is learned from updates that follow each other closely. The first move of a scroll comes after a
    /// pause, which says nothing about the app's pace: counting it would make the popup trail behind the text at
    /// the start of every scroll.
    private func glide(to layout: PopupLayout) {
        let target = layout.frame(for: displayedSize)
        let now = ContinuousClock.now
        if let lastFollowUpdate, now - lastFollowUpdate <= Self.longestUpdateGap {
            followUpdateInterval = (followUpdateInterval + min(now - lastFollowUpdate, Self.maximumGlide)) / 2
        }
        lastFollowUpdate = now
        guard followUpdateInterval >= Self.minimumGlide else {
            stopGlide()
            applyFrame(target)
            return
        }
        // Start from where the popup is now, measured at the edge that faces the selection.
        let current = popupFrame
        glideOffset = CGVector(
            dx: current.minX - target.minX,
            dy: layout.placement == .below ? current.maxY - target.maxY : current.minY - target.minY
        )
        glideStart = now
        glideDuration = followUpdateInterval
        glideTask?.cancel()
        glideTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: Self.glideFrameInterval)
                } catch {
                    return
                }
                guard let self, let layout = self.layout, self.isPresented else { return }
                self.applyFrame(self.glided(layout.frame(for: self.displayedSize)))
                if self.glideRemaining == 0 {
                    return
                }
            }
        }
    }

    /// `frame` shifted back by what is left of the current glide.
    private func glided(_ frame: CGRect) -> CGRect {
        let remaining = glideRemaining
        guard remaining > 0 else { return frame }
        return frame.offsetBy(dx: (glideOffset.dx * remaining).rounded(), dy: (glideOffset.dy * remaining).rounded())
    }

    private func stopGlide() {
        glideTask?.cancel()
        glideTask = nil
        glideDuration = .zero
    }
}
