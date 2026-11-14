//
//  SelectionGestureTests.swift
//  GlossTests
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import CoreGraphics
import Testing
@testable import Gloss

struct SelectionGestureTests {
    // MARK: - Selections

    @Test func testDragAcrossTextIsASelection() {
        #expect(SelectionGesture.classify(down: down(), up: up(at: CGPoint(x: 360, y: 300))) == .drag)
    }

    @Test func testTinyMovementIsAPlainClick() {
        #expect(SelectionGesture.classify(down: down(), up: up(at: CGPoint(x: 303, y: 302))) == nil)
    }

    @Test(arguments: [2, 3])
    func testMultiClickSelectsWordOrParagraph(clickCount: Int) {
        #expect(SelectionGesture.classify(down: down(), up: up(clickCount: clickCount)) == .multiClick(clickCount))
    }

    @Test func testShiftClickExtendsTheSelection() {
        #expect(SelectionGesture.classify(down: down(modifiers: .shift), up: up(modifiers: .shift)) == .shiftClick)
    }

    @Test func testPressWithoutAWindowStillCounts() {
        let gesture = SelectionGesture.classify(
            down: down(windowBounds: nil),
            up: up(at: CGPoint(x: 360, y: 300), windowBounds: nil)
        )
        #expect(gesture == .drag)
    }

    // MARK: - Not selections

    @Test(arguments: [PointerModifiers.command, PointerModifiers.control])
    func testCommandOrControlPressIsIgnored(modifier: PointerModifiers) {
        let gesture = SelectionGesture.classify(
            down: down(modifiers: modifier),
            up: up(at: CGPoint(x: 400, y: 300), modifiers: modifier)
        )
        #expect(gesture == nil)
    }

    @Test func testMovingTheWindowIsNotASelection() {
        let moved = Self.window.offsetBy(dx: 60, dy: 0)
        #expect(SelectionGesture.classify(down: down(), up: up(at: CGPoint(x: 360, y: 300), windowBounds: moved)) == nil)
    }

    @Test func testResizingTheWindowIsNotASelection() {
        var resized = Self.window
        resized.size.width += 40
        #expect(SelectionGesture.classify(down: down(), up: up(at: CGPoint(x: 360, y: 300), windowBounds: resized)) == nil)
    }

    @Test func testClosingTheWindowIsNotASelection() {
        #expect(SelectionGesture.classify(down: down(), up: up(at: CGPoint(x: 360, y: 300), windowBounds: nil)) == nil)
    }

    @Test func testDragAndDropIsNotASelection() {
        #expect(SelectionGesture.classify(down: down(), up: up(at: CGPoint(x: 360, y: 300), dragCount: 11)) == nil)
    }

    // MARK: - Behavior

    @Test func testDoubleClickWaitsLongerForAPossibleTripleClick() {
        #expect(SelectionGesture.multiClick(2).settleDelay > SelectionGesture.drag.settleDelay)
        #expect(SelectionGesture.multiClick(3).settleDelay == SelectionGesture.drag.settleDelay)
    }

    @Test func testShiftClickNeverUsesTheCopyFallback() {
        #expect(!SelectionGesture.shiftClick.allowsCopyFallback)
        #expect(SelectionGesture.drag.allowsCopyFallback)
        #expect(SelectionGesture.multiClick(2).allowsCopyFallback)
    }

    // MARK: - Private

    fileprivate static let window = CGRect(x: 100, y: 100, width: 800, height: 600)

    fileprivate func down(
        modifiers: PointerModifiers = [],
        windowBounds: CGRect? = SelectionGestureTests.window
    ) -> PointerDownContext {
        PointerDownContext(
            sample: sample(CGPoint(x: 300, y: 300), clickCount: 1, modifiers: modifiers),
            windowID: windowBounds == nil ? nil : 42,
            windowBounds: windowBounds,
            dragPasteboardChangeCount: 10
        )
    }

    fileprivate func up(
        at point: CGPoint = CGPoint(x: 300, y: 300),
        clickCount: Int = 1,
        modifiers: PointerModifiers = [],
        windowBounds: CGRect? = SelectionGestureTests.window,
        dragCount: Int = 10
    ) -> PointerUpContext {
        PointerUpContext(
            sample: sample(point, clickCount: clickCount, modifiers: modifiers),
            windowBounds: windowBounds,
            dragPasteboardChangeCount: dragCount
        )
    }

    private func sample(_ point: CGPoint, clickCount: Int, modifiers: PointerModifiers) -> PointerSample {
        PointerSample(quartzLocation: point, cocoaLocation: point, clickCount: clickCount, modifiers: modifiers)
    }
}

extension SelectionGestureTests {
    @Test func testRejectionExplainsWhyAPressIsNotASelection() {
        let moved = Self.window.offsetBy(dx: 60, dy: 0)
        #expect(SelectionGesture.rejection(down: down(), up: up(at: CGPoint(x: 360, y: 300), windowBounds: moved)) == .windowChanged)
        #expect(SelectionGesture.rejection(down: down(), up: up(at: CGPoint(x: 360, y: 300), dragCount: 11)) == .dragAndDrop)
        #expect(SelectionGesture.rejection(down: down(), up: up()) == .plainClick)
    }
}
