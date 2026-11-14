//
//  FirstLineBreak.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import AppKit
import CoreText

/// Finds where the first line of a text ends when that line has less room than the ones after it.
///
/// The popup's buttons sit beside the first line of the translation: only that line makes room for them, and the
/// lines below run the full width.
internal enum FirstLineBreak {
    // MARK: - Properties

    /// No line holds this many characters, so the end of the first one is never looked for beyond them.
    private static let lookahead = 600

    // MARK: - Splitting

    /// Splits `text` after its first line.
    /// - Parameters:
    ///   - text: The text to lay out.
    ///   - font: Font the text is drawn in.
    ///   - width: Room for the first line.
    /// - Returns: The first line, without the space or line break that ends it, and the text after it; that one is
    ///   empty when everything fits on the first line.
    internal static func split(_ text: String, font: NSFont, width: CGFloat) -> (firstLine: String, rest: String) {
        let full = text as NSString
        // Stop at a whole character: cutting a surrogate pair in half would leave an unpaired one behind.
        let headLength = full.length > lookahead
            ? full.rangeOfComposedCharacterSequence(at: lookahead).location
            : full.length
        let head = NSAttributedString(string: full.substring(to: headLength), attributes: [.font: font])
        let typesetter = CTTypesetterCreateWithAttributedString(head)
        let length = CTTypesetterSuggestLineBreak(typesetter, 0, Double(max(width, 1)))
        guard length > 0, length < full.length else { return (text, "") }
        let firstLine = full.substring(to: length)
            .replacing(/\s+$/, with: "")
        return (firstLine, full.substring(from: length))
    }
}
