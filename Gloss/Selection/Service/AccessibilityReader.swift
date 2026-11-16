//
//  AccessibilityReader.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import AppKit
import ApplicationServices
import os

/// Reads selections and menus of other apps through the Accessibility API.
///
/// AX calls block until the target app answers (up to the messaging timeout), so this actor runs on its own serial
/// queue instead of the main thread or the shared concurrency pool. `AXUIElement`s never leave the actor; callers
/// only get value types back.
internal actor AccessibilityReader {
    // MARK: - Types

    /// Who owns the point where a press started.
    internal enum TargetResult: Sendable {
        /// - Parameter isVerified: Whether the app told what is under the press. When it couldn't, all that is
        ///   known is that the press was in one of its windows.
        case accepted(processID: pid_t, isVerified: Bool)
        /// Not a selection: the reason is only logged.
        case rejected(String)
        /// Gloss lost its Accessibility permission.
        case apiDisabled
    }

    /// Outcome of reading an app's selection.
    internal enum ReadResult: Sendable {
        /// Selected text and, when the app reports them, its bounds and the frames of what clips it (the scroll
        /// areas it sits in, or its window), in Quartz coordinates. `isCorrected` tells that the app reported
        /// them somewhere else and Gloss worked out where they are.
        case text(String, bounds: CGRect?, clipFrames: [CGRect], isCorrected: Bool)
        /// The app answered and nothing is selected, or the focus is in a password field.
        case empty
        /// The app doesn't expose its selection through Accessibility.
        case unsupported
        /// Gloss lost its Accessibility permission.
        case apiDisabled
    }

    /// Where the selection last found by ``readSelection(processID:near:deadline:)`` is now.
    internal enum TrackedSelectionState: Sendable {
        /// The selection's bounds and the frames of what clips it (the scroll areas it sits in, or its window), in
        /// Quartz coordinates.
        case located(bounds: CGRect, clipFrames: [CGRect])
        /// The selected text changed, went away or its element no longer exists.
        case changed
        /// The app didn't answer; ask again later.
        case unavailable
    }

    private enum TextRead {
        case text(String)
        case empty
        case unsupported
        /// The element no longer exists.
        case gone
    }

    private struct TrackedSelection {
        let element: AXUIElement
        let text: String
        /// The scroll areas the selection sits in and its window: what clips it when it scrolls out of view.
        let surroundings: Surroundings
    }

    /// What an element sits in.
    private struct Surroundings {
        /// Every scroll area above the element, nearest first, each with the element that holds it.
        var scrollAreas: [(area: AXUIElement, host: AXUIElement?)]
        var window: AXUIElement?
    }

    /// Where a selection is on screen (Quartz coordinates).
    private struct Location {
        var bounds: CGRect
        /// Frames of the scroll areas the selection sits in, or of its window when it sits in none.
        var clipFrames: [CGRect]
        /// How far from there the app reported all of it, when it did.
        var correction: CGVector?
    }

    // MARK: - Properties

    internal nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    private nonisolated let queue = DispatchSerialQueue(label: "com.lorpaves.Gloss.accessibility")
    private let systemWide = AXUIElementCreateSystemWide()
    /// Apps already asked to build their accessibility tree.
    private var treeRequests: Set<pid_t> = []
    /// When an app agreed to build its tree; it may still be building it for a moment.
    private var treeEnabledAt: [pid_t: ContinuousClock.Instant] = [:]
    /// Apps whose full tree Gloss turned on with `AXEnhancedUserInterface`; turned off again when Gloss quits.
    private var enhancedProcessIDs: Set<pid_t> = []
    private var copyMenuItems: [pid_t: AXUIElement] = [:]
    /// The selection the popup is showing, re-read while it follows scrolling.
    private var trackedSelection: TrackedSelection?

    /// Presses starting on these are control interactions, not text selection.
    private static let rejectedRoles: Set<String> = [
        kAXScrollBarRole, kAXValueIndicatorRole, kAXSliderRole, kAXSplitterRole,
        kAXMenuBarRole, kAXMenuBarItemRole, kAXMenuItemRole, kAXButtonRole
    ]
    /// Only these roles' empty answers mean "nothing selected"; generic containers (Chrome's AXGroups without its
    /// full accessibility tree) answer an empty string too, even with text selected inside them.
    private static let textRoles: Set<String> = [
        kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole, kAXStaticTextRole, "AXWebArea"
    ]
    private static let maximumAncestors = 4
    /// How far up to look for the scroll areas that clip a selection; text in a web page can sit dozens of levels
    /// below its window.
    private static let maximumClipAncestors = 60
    /// Waits before asking a web view again while it connects the accessibility of its page (see ``hitTest(_:)``
    /// and ``focusedElement(of:asksAgain:)``); it usually answers the second time, some 20 ms later.
    private static let connectionRetryDelays: [Duration] = [
        .milliseconds(30), .milliseconds(60), .milliseconds(120), .milliseconds(240)
    ]
    /// Chromium turns its full tree on after a delay and then builds it per page, so allow a few seconds.
    private static let treeWarmUp = Duration.seconds(5)
    private static let enhancedUserInterface = "AXEnhancedUserInterface"
    private static let logger = Logger.gloss("AccessibilityReader")

    // MARK: - Lifecycle

    /// - Parameter messagingTimeout: Seconds to wait for an unresponsive app; set on the system-wide element it
    ///   applies to every AX call of the process (the system default is 6 seconds).
    internal init(messagingTimeout: Float = 0.5) {
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)
    }

    // MARK: - Hit testing

    /// Checks who owns the point where a press started.
    /// - Parameters:
    ///   - point: Mouse-down location (Quartz coordinates).
    ///   - frontmostProcessID: `NSWorkspace`'s frontmost app, used when the system-wide focus can't be read.
    ///   - windowOwnerProcessID: The process whose window is under the press, as the window server sees it.
    /// - Returns: `.accepted` for presses in the focused app's content; `.rejected` for Gloss itself, the Dock,
    ///   other apps' menu bar extras and controls such as scroll bars and buttons.
    internal func target(
        at point: CGPoint,
        frontmostProcessID: pid_t?,
        windowOwnerProcessID: pid_t?
    ) async -> TargetResult {
        let (hit, error) = await hitTest(point)
        if error == .apiDisabled {
            return .apiDisabled
        }
        guard let focusedPID = focusedProcessID(frontmostProcessID: frontmostProcessID) else {
            return .rejected("no focused app")
        }
        guard focusedPID != ProcessInfo.processInfo.processIdentifier else {
            return .rejected("Gloss has the focus")
        }
        guard error == .success, let hit else {
            // A web view that lost track of where its window is keeps answering "not implemented" for the places
            // the user really presses (seen with Safari 27). The window server still knows whose window that is.
            guard error == .notImplemented, windowOwnerProcessID == focusedPID else {
                return .rejected("no element at the press (AXError \(error.rawValue))")
            }
            Self.logger.debug("Process \(focusedPID) can't tell what is under the press; accepted by its window")
            return .accepted(processID: focusedPID, isVerified: false)
        }
        guard let hitPID = processID(of: hit) else {
            return .rejected("element without a process")
        }
        guard hitPID == focusedPID else {
            return .rejected("press outside the focused app")
        }
        if let role = string(hit, kAXRoleAttribute), Self.rejectedRoles.contains(role) {
            // The same web view may also name an element elsewhere on its page, whose role says nothing about
            // the press.
            guard isInItsWindow(surroundings(of: hit)) else {
                Self.logger.debug("Process \(hitPID) reports \(role) outside its window; accepted by its window")
                return .accepted(processID: hitPID, isVerified: false)
            }
            return .rejected("press on \(role)")
        }
        return .accepted(processID: hitPID, isVerified: true)
    }

    /// The app that has the keyboard focus.
    /// - Parameter frontmostProcessID: `NSWorkspace`'s frontmost app, used when the system-wide focus can't be read.
    internal func focusedProcessID(frontmostProcessID: pid_t?) -> pid_t? {
        // Prefer the live system-wide focus (NSWorkspace can lag behind the click that activated the app), but it
        // fails with kAXErrorCannotComplete while some apps are in front (Chrome), so fall back to NSWorkspace.
        element(systemWide, kAXFocusedApplicationAttribute).flatMap { processID(of: $0) } ?? frontmostProcessID
    }

    // MARK: - Selection

    /// Reads the selected text of an app: first from the element under `point` and a few of its ancestors, then
    /// from the app's focused element.
    /// - Parameters:
    ///   - processID: The app that owns the selection.
    ///   - point: Mouse-up location (Quartz coordinates); `nil` for a selection made with the keyboard, which is
    ///     read from the focused element and a few of its ancestors.
    ///   - deadline: Stop asking a slow app after this instant.
    /// - Returns: The selection, or why there is none. "Nothing selected" only counts when the element the user
    ///   pressed says so: the focused element may be elsewhere (in Chrome it's often the address bar), so its
    ///   empty answer alone doesn't rule out the copy fallback.
    /// - Throws: `CancellationError` when a newer press superseded this one.
    internal func readSelection(
        processID: pid_t,
        near point: CGPoint?,
        deadline: ContinuousClock.Instant
    ) async throws -> ReadResult {
        let app = AXUIElementCreateApplication(processID)
        // A press has the element under the pointer to go by; keys only have the focused one, so wait for it.
        let (focused, focusError) = await focusedElement(of: app, asksAgain: point == nil)
        if focusError == .apiDisabled {
            return .apiDisabled
        }
        try Task.checkCancellation()
        var pressed: [AXUIElement] = []
        if let point {
            let hit = await hitTest(point).element
            try Task.checkCancellation()
            pressed = hit.flatMap { self.processID(of: $0) == processID ? lineage(of: $0) : nil } ?? []
        }
        var candidates = pressed.map { (element: $0, isPressed: true) }
        if let focused, !pressed.contains(where: { CFEqual($0, focused) }) {
            // Without a press, the focused element's ancestors stand in for the pressed ones: the selection of a
            // web page is known to all of its elements, that of a text view to the view around its focused part.
            let elements = point == nil ? lineage(of: focused) : [focused]
            candidates += elements.map { (element: $0, isPressed: false) }
        }

        var pressedSaidEmpty = false
        var focusedSaidEmpty = false
        for candidate in candidates {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else {
                Self.logger.debug("Accessibility read of process \(processID) ran out of time")
                break
            }
            if string(candidate.element, kAXSubroleAttribute) == kAXSecureTextFieldSubrole {
                return .empty
            }
            switch selectedText(of: candidate.element) {
            case .text(let text):
                // Only a selection with bounds can be followed.
                guard let bounds = selectionBounds(of: candidate.element) else {
                    trackedSelection = nil
                    return .text(text, bounds: nil, clipFrames: [], isCorrected: false)
                }
                let surroundings = surroundings(of: candidate.element)
                guard let location = locate(bounds, in: surroundings) else {
                    // The text is right; where the app says it is can't be, and nothing tells where it is.
                    Self.logger.debug("Process \(processID) reports its selection outside its window; position ignored")
                    trackedSelection = nil
                    return .text(text, bounds: nil, clipFrames: [], isCorrected: false)
                }
                if let correction = location.correction {
                    Self.logger.debug(
                        "Process \(processID) reports its selection (\(correction.dx), \(correction.dy)) from its window; moved back"
                    )
                }
                trackedSelection = TrackedSelection(element: candidate.element, text: text, surroundings: surroundings)
                return .text(
                    text,
                    bounds: location.bounds,
                    clipFrames: location.clipFrames,
                    isCorrected: location.correction != nil
                )
            case .empty:
                if candidate.isPressed {
                    pressedSaidEmpty = true
                } else {
                    focusedSaidEmpty = true
                }
            case .unsupported, .gone:
                continue
            }
        }
        if pressedSaidEmpty || (pressed.isEmpty && focusedSaidEmpty) {
            return .empty
        }
        return .unsupported
    }

    // MARK: - Tracking

    /// Re-reads the selection that ``readSelection(processID:near:deadline:)`` last found, so the popup can follow
    /// it while the user scrolls or the window moves.
    /// - Parameter verifiesText: Also check that the same text is still selected (one more call to the app).
    internal func trackedSelectionState(verifiesText: Bool) -> TrackedSelectionState {
        guard let tracked = trackedSelection else { return .changed }
        if verifiesText {
            switch selectedText(of: tracked.element) {
            case .text(let text) where text == tracked.text:
                break
            case .text, .empty, .gone:
                return .changed
            case .unsupported:
                return .unavailable
            }
        }
        guard let bounds = selectionBounds(of: tracked.element),
              let location = locate(bounds, in: tracked.surroundings)
        else { return .unavailable }
        return .located(bounds: location.bounds, clipFrames: location.clipFrames)
    }

    /// Forgets the tracked selection.
    internal func stopTrackingSelection() {
        trackedSelection = nil
    }

    // MARK: - Accessibility tree

    /// Asks an app once to build its full accessibility tree, so that its selections report their text and where
    /// they are on screen.
    ///
    /// Electron apps accept `AXManualAccessibility`. Chromium browsers (Chrome, Edge, Brave…) reject it and only
    /// build the tree of their web pages for `AXEnhancedUserInterface`, the attribute VoiceOver sets; Gloss turns
    /// that one off again when it quits (``restoreAccessibilityModes()``). Other apps reject both, which is harmless.
    /// - Parameters:
    ///   - processID: The app.
    ///   - bundleURL: Where the app is installed, to recognize Chromium browsers.
    internal func enableAccessibilityTree(for processID: pid_t, bundleURL: URL?) {
        guard treeRequests.insert(processID).inserted else { return }
        let app = AXUIElementCreateApplication(processID)
        if AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, NSNumber(value: true)) == .success {
            treeEnabledAt[processID] = .now
            Self.logger.debug("Enabled the accessibility tree of process \(processID)")
            return
        }
        guard Self.isChromiumBrowser(bundleURL: bundleURL) else { return }
        if (attribute(app, Self.enhancedUserInterface) as? Bool) == true {
            // Already on (VoiceOver or another tool): leave it to whoever turned it on.
            return
        }
        let error = AXUIElementSetAttributeValue(app, Self.enhancedUserInterface as CFString, NSNumber(value: true))
        // Chrome applies the value yet answers kAXErrorNotImplemented, so trust what it reads back.
        guard (attribute(app, Self.enhancedUserInterface) as? Bool) == true else {
            Self.logger.debug("Process \(processID) refused AXEnhancedUserInterface (AXError \(error.rawValue))")
            return
        }
        treeEnabledAt[processID] = .now
        enhancedProcessIDs.insert(processID)
        Self.logger.notice("Turned on the full accessibility tree of browser process \(processID)")
    }

    /// Turns `AXEnhancedUserInterface` off again in the apps where Gloss turned it on.
    internal func restoreAccessibilityModes() {
        for processID in enhancedProcessIDs {
            let app = AXUIElementCreateApplication(processID)
            let error = AXUIElementSetAttributeValue(app, Self.enhancedUserInterface as CFString, NSNumber(value: false))
            // As when turning it on, the error code is unreliable; the browser may also have quit in the meantime.
            if (attribute(app, Self.enhancedUserInterface) as? Bool) == true {
                Self.logger.debug("Couldn't restore the accessibility mode of process \(processID) (AXError \(error.rawValue))")
            }
        }
        enhancedProcessIDs.removeAll()
    }

    /// Whether an app is a Chromium web browser: it ships a "… Framework.framework" (as Chrome, Edge and Brave do)
    /// and opens web links. Electron apps ship such a framework too, but don't open web links.
    internal nonisolated static func isChromiumBrowser(bundleURL: URL?) -> Bool {
        guard let bundleURL,
              let frameworks = try? FileManager.default.contentsOfDirectory(
                  atPath: bundleURL.appending(path: "Contents/Frameworks").path
              ),
              frameworks.contains(where: { $0.hasSuffix(" Framework.framework") })
        else { return false }
        let urlTypes = Bundle(url: bundleURL)?.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        return (urlTypes ?? []).contains { ($0["CFBundleURLSchemes"] as? [String])?.contains("https") == true }
    }

    /// Whether an app's tree was enabled so recently that it may still be building.
    internal func isTreeWarmingUp(for processID: pid_t) -> Bool {
        guard let enabledAt = treeEnabledAt[processID] else { return false }
        return ContinuousClock.now - enabledAt < Self.treeWarmUp
    }

    // MARK: - Copy menu

    /// Presses the app's Copy menu item (the one with the ⌘C shortcut), so the app copies its own selection.
    ///
    /// Pressing the item instead of synthesizing ⌘C avoids the alert sound when nothing is selected, works with
    /// any keyboard layout and doesn't mix with keys the user is holding. `AXEnabled` isn't consulted because it
    /// can be stale for menus that were never opened; the pasteboard's change count tells whether anything was
    /// copied.
    /// - Returns: Whether a Copy item was found and pressed.
    internal func pressCopyMenuItem(processID: pid_t) -> Bool {
        if let cached = copyMenuItems[processID], isCopyItem(cached), press(cached) {
            return true
        }
        copyMenuItems[processID] = nil
        guard let item = findCopyMenuItem(in: AXUIElementCreateApplication(processID)) else {
            Self.logger.debug("No Copy menu item in process \(processID)")
            return false
        }
        copyMenuItems[processID] = item
        return press(item)
    }

    // MARK: - Private

    private func selectedText(of element: AXUIElement) -> TextRead {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value)
        if error == .invalidUIElement {
            return .gone
        }
        if error == .success, let text = value as? String, !text.isEmpty {
            return .text(text)
        }
        // Web content (WebKit, Chromium) exposes its selection as a text marker range.
        if let markerRange = attribute(element, kAXSelectedTextMarkerRangeAttribute),
           let text = parameterizedAttribute(
               element,
               kAXStringForTextMarkerRangeParameterizedAttribute,
               parameter: markerRange
           ) as? String,
           !text.isEmpty {
            return .text(text)
        }
        let isTextElement = string(element, kAXRoleAttribute).map { Self.textRoles.contains($0) } ?? false
        return isTextElement && (error == .success || error == .noValue) ? .empty : .unsupported
    }

    /// Where the selection is on screen (Quartz coordinates).
    ///
    /// Web content answers with text markers first: they cover the whole selection from any element of the page,
    /// while Chrome's paragraphs and web area answer the text-range question with an empty rectangle. Native text
    /// views only know text ranges. Empty rectangles (a tree that isn't laid out yet) count as no answer.
    private func selectionBounds(of element: AXUIElement) -> CGRect? {
        if let markerRange = attribute(element, kAXSelectedTextMarkerRangeAttribute),
           let rect = rect(from: parameterizedAttribute(
               element,
               kAXBoundsForTextMarkerRangeParameterizedAttribute,
               parameter: markerRange
           )),
           ScreenGeometry.isMeasurable(rect) {
            return rect
        }
        if let range = attribute(element, kAXSelectedTextRangeAttribute),
           let rect = rect(from: parameterizedAttribute(
               element,
               kAXBoundsForRangeParameterizedAttribute,
               parameter: range
           )),
           ScreenGeometry.isMeasurable(rect) {
            return rect
        }
        return nil
    }

    /// Every scroll area above `element` and its window: whatever clips the text when it scrolls out of view.
    ///
    /// The nearest scroll area alone isn't enough. A web view laid out at its full height inside a native scroll
    /// view (Xcode's Quick Help) has a scroll area of its own that moves with the text and never clips it; the
    /// one that does is further up.
    private func surroundings(of element: AXUIElement) -> Surroundings {
        var scrollAreas: [(area: AXUIElement, host: AXUIElement?)] = []
        var window: AXUIElement?
        var ancestor = self.element(element, kAXParentAttribute)
        for _ in 0..<Self.maximumClipAncestors {
            guard let current = ancestor else { break }
            let (role, parent) = roleAndParent(of: current)
            if role == kAXScrollAreaRole {
                scrollAreas.append((area: current, host: parent))
            } else if role == kAXWindowRole {
                window = current
                break
            } else if role == kAXApplicationRole {
                break
            }
            ancestor = parent
        }
        return Surroundings(scrollAreas: scrollAreas, window: window ?? self.element(element, kAXWindowAttribute))
    }

    /// Screen frames of the scroll areas in `surroundings`, leaving out those that don't report a usable one.
    private func scrollAreaFrames(of surroundings: Surroundings) -> [(frame: CGRect, host: AXUIElement?)] {
        surroundings.scrollAreas.compactMap { scrollArea in
            guard let frame = frame(of: scrollArea.area), ScreenGeometry.isMeasurable(frame) else { return nil }
            return (frame: frame, host: scrollArea.host)
        }
    }

    private func windowFrame(of surroundings: Surroundings) -> CGRect? {
        surroundings.window.flatMap { frame(of: $0) }.flatMap { ScreenGeometry.isMeasurable($0) ? $0 : nil }
    }

    /// Whether the scroll areas around an element are where its window is, as far as that can be told (see
    /// ``ScreenGeometry/areFrames(_:insideWindowWithFrame:)``).
    private func isInItsWindow(_ surroundings: Surroundings) -> Bool {
        guard let windowFrame = windowFrame(of: surroundings) else { return true }
        return ScreenGeometry.areFrames(scrollAreaFrames(of: surroundings).map(\.frame), insideWindowWithFrame: windowFrame)
    }

    /// Works out where a selection is from the bounds the app reports for it.
    ///
    /// Usually that is where the app says. A web view whose page lost track of its window reports the page's
    /// scroll area, and everything in it, the same distance away from where they are; the view that holds that
    /// scroll area is reported by the app itself, in place, which gives the distance away (see
    /// ``ScreenGeometry/misplacement(ofScrollAreaWithFrame:inViewWithFrame:)``).
    /// - Returns: `nil` when the app's answers can't be right and can't be put right.
    private func locate(_ bounds: CGRect, in surroundings: Surroundings) -> Location? {
        let windowFrame = windowFrame(of: surroundings)
        let scrollAreas = scrollAreaFrames(of: surroundings)
        guard !scrollAreas.isEmpty else {
            return Location(bounds: bounds, clipFrames: windowFrame.map { [$0] } ?? [], correction: nil)
        }
        guard let windowFrame, let misplaced = scrollAreas.last(where: { !$0.frame.intersects(windowFrame) }) else {
            return Location(bounds: bounds, clipFrames: scrollAreas.map(\.frame), correction: nil)
        }
        guard let viewFrame = misplaced.host.flatMap({ frame(of: $0) }),
              viewFrame.intersects(windowFrame),
              let correction = ScreenGeometry.misplacement(
                  ofScrollAreaWithFrame: misplaced.frame,
                  inViewWithFrame: viewFrame
              )
        else { return nil }
        // Scroll areas of the app itself, further up, are where they say.
        let clipFrames = scrollAreas.map { scrollArea in
            scrollArea.frame.intersects(windowFrame)
                ? scrollArea.frame
                : scrollArea.frame.offsetBy(dx: -correction.dx, dy: -correction.dy)
        }
        guard ScreenGeometry.areFrames(clipFrames, insideWindowWithFrame: windowFrame) else { return nil }
        return Location(
            bounds: bounds.offsetBy(dx: -correction.dx, dy: -correction.dy),
            clipFrames: clipFrames,
            correction: correction
        )
    }

    /// An element's role and parent, asked for together: climbing a deep tree costs one call per level.
    private func roleAndParent(of element: AXUIElement) -> (role: String?, parent: AXUIElement?) {
        guard let values = attributes(element, [kAXRoleAttribute, kAXParentAttribute]) else {
            return (string(element, kAXRoleAttribute), self.element(element, kAXParentAttribute))
        }
        return (values[0] as? String, axElement(values[1]))
    }

    /// Screen frame of an element (Quartz coordinates).
    private func frame(of element: AXUIElement) -> CGRect? {
        let values = attributes(element, [kAXPositionAttribute, kAXSizeAttribute])
        guard let origin = point(from: values?[0] ?? attribute(element, kAXPositionAttribute)),
              let size = size(from: values?[1] ?? attribute(element, kAXSizeAttribute))
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// The app's Copy item: directly in one of its menus, or one level down in a submenu (Xcode keeps it under
    /// Edit ▸ Copy ▸ Copy).
    private func findCopyMenuItem(in app: AXUIElement) -> AXUIElement? {
        guard let menuBar = element(app, kAXMenuBarAttribute) else { return nil }
        var menus: [[AXUIElement]] = []
        // Skip the Apple menu; Copy lives in the app's Edit menu.
        for barItem in children(of: menuBar).dropFirst() {
            for menu in children(of: barItem) {
                let items = children(of: menu)
                if let item = items.first(where: { isCopyItem($0) }) {
                    return item
                }
                menus.append(items)
            }
        }
        for items in menus {
            for item in items {
                for submenu in children(of: item) {
                    if let nested = children(of: submenu).first(where: { isCopyItem($0) }) {
                        return nested
                    }
                }
            }
        }
        return nil
    }

    private func isCopyItem(_ item: AXUIElement) -> Bool {
        let attributes = [kAXMenuItemCmdCharAttribute, kAXMenuItemCmdModifiersAttribute] as CFArray
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(item, attributes, [], &values) == .success,
              let list = values as? [Any], list.count == 2,
              let character = list[0] as? String,
              let modifiers = list[1] as? Int
        else { return false }
        // A modifier mask of 0 means ⌘ alone (kAXMenuItemModifierNone).
        return character.caseInsensitiveCompare("C") == .orderedSame && modifiers == 0
    }

    private func press(_ item: AXUIElement) -> Bool {
        AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    /// The element at `point` (Quartz coordinates), or why there is none.
    ///
    /// A web view only connects the accessibility of its page when it is first asked about it: that first question
    /// fails with `kAXErrorNotImplemented`, and the same question a moment later is answered. Without asking again,
    /// the first selection in every newly loaded page (Xcode's Quick Help, for one) would be ignored.
    private func hitTest(_ point: CGPoint) async -> (element: AXUIElement?, error: AXError) {
        var remainingDelays = Self.connectionRetryDelays[...]
        while true {
            var hit: AXUIElement?
            let hitError = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit)
            guard hitError == .notImplemented, let delay = remainingDelays.popFirst() else {
                return (hitError == .success ? hit : nil, hitError)
            }
            do {
                try await Task.sleep(for: delay)
            } catch {
                // A newer press replaced this one.
                return (nil, hitError)
            }
        }
    }

    /// The app's focused element, or why there is none.
    ///
    /// As with ``hitTest(_:)``, a web view only connects the accessibility of its page when it is first asked
    /// about it: that first time the app answers that nothing has the focus (`kAXErrorNoValue`), and names the
    /// element a moment later. Without asking again, the first selection made with the keyboard in every newly
    /// loaded page would be ignored.
    /// - Parameter asksAgain: Whether to ask again while the app names no element.
    private func focusedElement(of app: AXUIElement, asksAgain: Bool) async -> (element: AXUIElement?, error: AXError) {
        var remainingDelays = asksAgain ? Self.connectionRetryDelays[...] : []
        while true {
            var value: CFTypeRef?
            let focusError = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value)
            if let element = axElement(value) {
                return (element, focusError)
            }
            guard focusError != .apiDisabled, let delay = remainingDelays.popFirst() else {
                return (nil, focusError)
            }
            do {
                try await Task.sleep(for: delay)
            } catch {
                // A newer press or key replaced this one.
                return (nil, focusError)
            }
        }
    }

    /// The element and up to ``maximumAncestors`` of its ancestors, nearest first.
    private func lineage(of element: AXUIElement) -> [AXUIElement] {
        var result = [element]
        var current = element
        while result.count <= Self.maximumAncestors, let parent = self.element(current, kAXParentAttribute) {
            result.append(parent)
            current = parent
        }
        return result
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    /// Several attributes in one round trip to the app, in the order of `names`; one the element doesn't have
    /// comes back as an error value, which the typed readers below turn into `nil`.
    /// - Returns: `nil` when the app doesn't answer the combined question.
    private func attributes(_ element: AXUIElement, _ names: [String]) -> [CFTypeRef]? {
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, names as CFArray, [], &values) == .success,
              let list = values as? [CFTypeRef], list.count == names.count
        else { return nil }
        return list
    }

    private func parameterizedAttribute(_ element: AXUIElement, _ name: String, parameter: CFTypeRef) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, name as CFString, parameter, &value) == .success else {
            return nil
        }
        return value
    }

    private func element(_ parent: AXUIElement, _ name: String) -> AXUIElement? {
        axElement(attribute(parent, name))
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        guard let array = attribute(element, kAXChildrenAttribute) as? [AnyObject] else { return [] }
        return array.compactMap { axElement($0) }
    }

    private func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    private func processID(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid > 0 else { return nil }
        return pid
    }

    /// Casts only after checking the CF type, so an app returning an unexpected value can't crash Gloss.
    private func axElement(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func point(from value: CFTypeRef?) -> CGPoint? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        var point = CGPoint.zero
        guard AXValueGetType(axValue) == .cgPoint, AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func size(from value: CFTypeRef?) -> CGSize? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        var size = CGSize.zero
        guard AXValueGetType(axValue) == .cgSize, AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

    private func rect(from value: CFTypeRef?) -> CGRect? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        var rect = CGRect.zero
        guard AXValueGetType(axValue) == .cgRect, AXValueGetValue(axValue, .cgRect, &rect) else { return nil }
        return rect
    }
}
