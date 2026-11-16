//
//  KeyboardSelectionTrackerTests.swift
//  GlossTests
//
//  Created by Lorpaves on 2026/11/16.
//

import Foundation
import Testing
@testable import Gloss

struct KeyboardSelectionTrackerTests {
    // MARK: - Select all

    @Test func testSelectAllIsReadAsSoonAsItIsPressed() {
        var tracker = KeyboardSelectionTracker()
        #expect(tracker.keyDown(keyCode: 0, characters: "a", modifiers: .command, isRepeat: false) == .selectAll)
    }

    @Test func testHoldingSelectAllIsReadOnce() {
        var tracker = KeyboardSelectionTracker()
        _ = tracker.keyDown(keyCode: 0, characters: "a", modifiers: .command, isRepeat: false)
        #expect(tracker.keyDown(keyCode: 0, characters: "a", modifiers: .command, isRepeat: true) == nil)
    }

    // MARK: - Extending with Shift

    @Test func testExtendedSelectionIsReadWhenShiftIsLetGo() {
        var tracker = KeyboardSelectionTracker()
        #expect(tracker.keyDown(keyCode: Self.right, characters: nil, modifiers: .shift, isRepeat: false) == nil)
        #expect(tracker.keyDown(keyCode: Self.right, characters: nil, modifiers: .shift, isRepeat: true) == nil)
        #expect(tracker.modifiersChanged(to: []) == .extend)
    }

    @Test func testLettingShiftGoIsReportedOnce() {
        var tracker = KeyboardSelectionTracker()
        _ = tracker.keyDown(keyCode: Self.right, characters: nil, modifiers: .shift, isRepeat: false)
        _ = tracker.modifiersChanged(to: [])
        #expect(tracker.modifiersChanged(to: []) == nil)
    }

    /// ⌥ comes and goes while the user switches between extending by character and by word.
    @Test func testOtherModifiersChangingKeepTheSelectionGoing() {
        var tracker = KeyboardSelectionTracker()
        _ = tracker.keyDown(keyCode: Self.right, characters: nil, modifiers: [.shift, .option], isRepeat: false)
        #expect(tracker.modifiersChanged(to: .shift) == nil)
        #expect(tracker.modifiersChanged(to: []) == .extend)
    }

    @Test func testShiftAloneSelectsNothing() {
        var tracker = KeyboardSelectionTracker()
        #expect(tracker.modifiersChanged(to: .shift) == nil)
        #expect(tracker.modifiersChanged(to: []) == nil)
    }

    @Test func testTypingOverTheSelectionLeavesNothingToRead() {
        var tracker = KeyboardSelectionTracker()
        _ = tracker.keyDown(keyCode: Self.right, characters: nil, modifiers: .shift, isRepeat: false)
        _ = tracker.keyDown(keyCode: 0, characters: "A", modifiers: .shift, isRepeat: false)
        #expect(tracker.modifiersChanged(to: []) == nil)
    }

    // MARK: - Private

    private static let right: UInt16 = 124
}
