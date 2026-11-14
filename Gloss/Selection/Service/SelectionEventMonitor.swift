//
//  SelectionEventMonitor.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import AppKit

/// Watches mouse events in other apps and reports them as ``SelectionSignal``s.
///
/// Global monitors never see events aimed at Gloss's own windows, so clicks in the popup don't show up here.
@MainActor
internal final class SelectionEventMonitor {
    // MARK: - Properties

    /// Signals in event order; consumed by a single task for the app's lifetime.
    internal let signals: AsyncStream<SelectionSignal>
    /// Whether scroll events are reported; only needed while the popup follows its selection.
    internal var reportsScrolling = false

    private let continuation: AsyncStream<SelectionSignal>.Continuation
    private var monitors: [Any] = []
    private var pendingDown: PointerDownContext?

    // MARK: - Lifecycle

    internal init() {
        (signals, continuation) = AsyncStream.makeStream(
            of: SelectionSignal.self,
            bufferingPolicy: .bufferingNewest(64)
        )
    }

    // MARK: - Actions

    /// Starts monitoring; call once Accessibility is granted (and again after it was revoked and re-granted).
    internal func start() {
        guard monitors.isEmpty else { return }
        let downMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: downMask, handler: { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleMouseDown(event)
            }
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleMouseUp(event)
            }
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleScroll(event)
            }
        }) {
            monitors.append(monitor)
        }
    }

    /// Stops monitoring (e.g. after Accessibility was revoked).
    internal func stop() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
        pendingDown = nil
    }

    // MARK: - Private

    private func handleMouseDown(_ event: NSEvent) {
        let sample = Self.sample(of: event)
        if event.type == .leftMouseDown {
            let windowNumber = NSWindow.windowNumber(at: sample.cocoaLocation, belowWindowWithWindowNumber: 0)
            let windowID = windowNumber > 0 ? CGWindowID(windowNumber) : nil
            pendingDown = PointerDownContext(
                sample: sample,
                windowID: windowID,
                windowBounds: windowID.flatMap(ScreenGeometry.windowBounds(of:)),
                dragPasteboardChangeCount: NSPasteboard(name: .drag).changeCount
            )
        } else {
            pendingDown = nil
        }
        continuation.yield(.pointerDown(sample))
    }

    private func handleMouseUp(_ event: NSEvent) {
        guard let down = pendingDown else { return }
        pendingDown = nil
        let up = PointerUpContext(
            sample: Self.sample(of: event),
            windowBounds: down.windowID.flatMap(ScreenGeometry.windowBounds(of:)),
            dragPasteboardChangeCount: NSPasteboard(name: .drag).changeCount
        )
        continuation.yield(.pointerUp(down: down, up: up))
    }

    private func handleScroll(_ event: NSEvent) {
        guard reportsScrolling, event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 else { return }
        // Global events have no window, so `locationInWindow` is in screen (Cocoa) coordinates.
        continuation.yield(.scroll(at: event.locationInWindow))
    }

    private static func sample(of event: NSEvent) -> PointerSample {
        // Global events have no window, so `locationInWindow` is in screen (Cocoa) coordinates.
        let cocoaLocation = event.locationInWindow
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let quartzLocation = event.cgEvent?.location
            ?? ScreenGeometry.flipped(cocoaLocation, primaryScreenHeight: primaryHeight)
        return PointerSample(
            quartzLocation: quartzLocation,
            cocoaLocation: cocoaLocation,
            clickCount: event.clickCount,
            modifiers: modifiers(of: event.modifierFlags)
        )
    }

    private static func modifiers(of flags: NSEvent.ModifierFlags) -> PointerModifiers {
        var modifiers: PointerModifiers = []
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }
}
