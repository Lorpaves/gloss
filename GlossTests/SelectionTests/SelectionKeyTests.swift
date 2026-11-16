//
//  SelectionKeyTests.swift
//  GlossTests
//
//  Created by Lorpaves on 2026/11/16.
//

import Foundation
import Testing
@testable import Gloss

struct SelectionKeyTests {
    // MARK: - Selections

    @Test(arguments: ["a", "A"])
    func testCommandASelectsEverything(characters: String) {
        #expect(SelectionKey.classify(keyCode: 0, characters: characters, modifiers: .command) == .selectAll)
    }

    /// The letter A isn't on the same key in every layout (Dvorak, AZERTY), so its key code doesn't matter.
    @Test func testCommandAIsRecognizedByItsLetter() {
        #expect(SelectionKey.classify(keyCode: 12, characters: "a", modifiers: .command) == .selectAll)
        #expect(SelectionKey.classify(keyCode: 0, characters: "q", modifiers: .command) == nil)
    }

    @Test(arguments: [Key.left, Key.right, Key.down, Key.up, Key.home, Key.end, Key.pageUp, Key.pageDown])
    func testShiftWithANavigationKeyExtendsTheSelection(keyCode: UInt16) {
        #expect(SelectionKey.classify(keyCode: keyCode, characters: nil, modifiers: .shift) == .extend)
    }

    @Test(arguments: [PointerModifiers.option, PointerModifiers.command])
    func testShiftExtendsByWordsAndLinesToo(modifier: PointerModifiers) {
        #expect(SelectionKey.classify(keyCode: Key.right, characters: nil, modifiers: [.shift, modifier]) == .extend)
    }

    // MARK: - Not selections

    @Test func testArrowKeyAloneOnlyMovesTheCaret() {
        #expect(SelectionKey.classify(keyCode: Key.right, characters: nil, modifiers: []) == nil)
    }

    @Test func testControlWithArrowKeysSwitchesSpaces() {
        #expect(SelectionKey.classify(keyCode: Key.right, characters: nil, modifiers: [.shift, .control]) == nil)
    }

    @Test func testTypingALetterIsNotASelection() {
        #expect(SelectionKey.classify(keyCode: 0, characters: "a", modifiers: []) == nil)
        #expect(SelectionKey.classify(keyCode: 0, characters: "A", modifiers: .shift) == nil)
    }

    @Test(arguments: [PointerModifiers.shift, PointerModifiers.option, PointerModifiers.control])
    func testOtherShortcutsWithAAreNotSelectAll(modifier: PointerModifiers) {
        #expect(SelectionKey.classify(keyCode: 0, characters: "a", modifiers: [.command, modifier]) == nil)
    }

    // MARK: - Private

    fileprivate enum Key {
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let down: UInt16 = 125
        static let up: UInt16 = 126
        static let home: UInt16 = 115
        static let end: UInt16 = 119
        static let pageUp: UInt16 = 116
        static let pageDown: UInt16 = 121
    }
}
