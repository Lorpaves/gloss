//
//  EscapeKeyInterceptor.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import AppKit
import CoreGraphics
import os

/// Swallows Esc while an unpinned popup is visible, so Esc closes the popup without reaching the app below
/// (where it would, say, open Xcode's completion list or leave Safari's full screen).
///
/// The event tap only exists while the popup is visible and only looks at key codes. It needs Accessibility, and
/// secure input (password fields) blocks it; the popup then closes on outside clicks only.
@MainActor
internal final class EscapeKeyInterceptor {
    // MARK: - Properties

    /// One element per swallowed Esc.
    internal let presses: AsyncStream<Void>
    /// Whether Esc is swallowed right now.
    internal var isArmed = false

    private let continuation: AsyncStream<Void>.Continuation
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    private static let escapeKeyCode: Int64 = 53
    private static let logger = Logger.gloss("EscapeKeyInterceptor")

    // MARK: - Lifecycle

    internal init() {
        (presses, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    }

    // MARK: - Actions

    /// Installs the event tap on the main run loop.
    internal func start() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: escapeTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Self.logger.notice("Esc tap unavailable; the popup closes on outside clicks only")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
    }

    /// Removes the event tap.
    internal func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
    }

    // MARK: - Tap

    /// Handles one tapped event on the main thread.
    /// - Returns: Whether to swallow the event.
    fileprivate func handle(type: CGEventType, keyCode: Int64) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return false
        case .keyDown where keyCode == Self.escapeKeyCode && isArmed:
            continuation.yield()
            return true
        default:
            return false
        }
    }
}

/// C callback of the Esc tap. Its run loop source is on the main run loop, so it runs on the main thread.
private func escapeTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let interceptor = Unmanaged<EscapeKeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
    let swallow = MainActor.assumeIsolated {
        interceptor.handle(type: type, keyCode: keyCode)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
