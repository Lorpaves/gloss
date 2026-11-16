//
//  PopupContentView.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import SwiftUI
import AppKit

/// The popup: the translation, with small copy and pin buttons in its top-right corner (and close while pinned).
///
/// Only the first line of the translation makes room for the buttons; the lines below run the full width. The view
/// reports its natural size, so the window fits the text up to the maximum size; longer text scrolls beneath the
/// buttons.
internal struct PopupContentView: View {
    // MARK: - Properties

    internal var model: PopupViewModel
    internal var settingsStore: SettingsStore
    internal var onTogglePin: () -> Void
    internal var onClose: () -> Void
    /// Reports the content's natural size so the window can match it.
    internal var onSizeChange: (CGSize) -> Void

    /// Natural size of the translation, measured at the widest the popup allows.
    @State private var textSize: CGSize = .zero
    @State private var didCopy = false
    /// The translation is scrolled, so its text passes beneath the buttons.
    @State private var isScrolled = false

    private static let verticalPadding: CGFloat = 14
    /// Space between the end of the first line and the buttons.
    private static let toolbarGap: CGFloat = 8
    /// Padding of the buttons inside their backing, which shows while text scrolls beneath them.
    private static let toolbarPadding = CGSize(width: 4, height: 2)
    /// Distance from the popup's right edge to that backing; the icons then end near the text's right edge.
    private static let toolbarInset: CGFloat = 6
    private static let buttonSize = CGSize(width: 22, height: 20)
    private static let buttonSpacing: CGFloat = 2

    // MARK: - Body

    internal var body: some View {
        let generation = model.generation
        content
            .fixedSize()
            .onGeometryChange(for: SizeReport.self) { proxy in
                SizeReport(size: proxy.size, generation: generation)
            } action: { report in
                onSizeChange(report.size)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: model.generation) {
                didCopy = false
                isScrolled = false
            }
            .task(id: didCopy) {
                guard didCopy else { return }
                do {
                    try await Task.sleep(for: .seconds(1.2))
                    didCopy = false
                } catch {
                    // Cancelled because the popup changed; the next copy resets the icon anyway.
                    return
                }
            }
    }

    private var content: some View {
        main
            .padding(.horizontal, PopupLayout.contentInset)
            .padding(.vertical, Self.verticalPadding)
            .overlay(alignment: .topTrailing) {
                toolbar
                    .padding(.top, toolbarTopInset)
                    .padding(.trailing, Self.toolbarInset)
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var main: some View {
        switch model.phase {
        case .waiting:
            // Explicitly circular: the default can render as a bar that stretches the popup to its widest.
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .frame(height: lineHeight)
                .padding(.trailing, toolbarReserve)
        case .translating, .finished:
            translationText
        case .failed:
            message("翻译失败")
        }
    }

    private var translationText: some View {
        let lines = FirstLineBreak.split(model.translation, font: font, width: maxTextWidth - toolbarReserve)
        return ScrollView(.vertical) {
            flowingText(lines)
                .frame(width: textSize.width, alignment: .leading)
        }
        .scrollIndicators(.automatic)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 1
        } action: { _, scrolled in
            isScrolled = scrolled
        }
        .frame(width: textSize.width, height: min(textSize.height, maxTextHeight))
        .background(alignment: .topLeading) {
            // Measures the text at the widest the popup allows, independent of the window's current size.
            ProposedWidthLayout(width: maxTextWidth) {
                flowingText(lines)
            }
            .hidden()
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                textSize = size
            }
        }
    }

    /// The translation with its first line cut short, which leaves the top-right corner to the buttons.
    private func flowingText(_ lines: (firstLine: String, rest: String)) -> some View {
        VStack(alignment: .leading, spacing: lineSpacing) {
            styled(lines.firstLine)
                .fixedSize()
                .padding(.trailing, toolbarReserve)
            if !lines.rest.isEmpty {
                styled(lines.rest)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func styled(_ text: String) -> some View {
        Text(text)
            .font(.system(size: fontSize))
            .lineSpacing(lineSpacing)
    }

    private func message(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(height: lineHeight)
            .padding(.trailing, toolbarReserve)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: Self.buttonSpacing) {
            iconButton(didCopy ? "checkmark" : "doc.on.doc", label: "复制") {
                model.copyTranslation()
                didCopy = true
            }
            .disabled(model.translation.isEmpty)
            iconButton(model.isPinned ? "pin.fill" : "pin", label: model.isPinned ? "取消固定" : "固定") {
                onTogglePin()
            }
            if model.isPinned {
                iconButton("xmark", label: "关闭") {
                    onClose()
                }
            }
        }
        .padding(.horizontal, Self.toolbarPadding.width)
        .padding(.vertical, Self.toolbarPadding.height)
        .background {
            // Text scrolling beneath the buttons would show through them.
            Capsule()
                .fill(.regularMaterial)
                .opacity(isScrolled ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.15), value: isScrolled)
    }

    private func iconButton(
        _ systemImage: String,
        label: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .frame(width: Self.buttonSize.width, height: Self.buttonSize.height)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(label)
        .accessibilityLabel(label)
    }

    // MARK: - Private

    private var fontSize: CGFloat {
        settingsStore.settings.translationFontSize
    }

    private var font: NSFont {
        .systemFont(ofSize: fontSize)
    }

    /// Height of one line of the translation; the spinner and the messages take the same.
    private var lineHeight: CGFloat {
        let font = font
        return (font.ascender - font.descender + font.leading).rounded(.up)
    }

    private var lineSpacing: CGFloat {
        (fontSize * 0.2).rounded()
    }

    private var toolbarWidth: CGFloat {
        let count: CGFloat = model.isPinned ? 3 : 2
        return count * Self.buttonSize.width + (count - 1) * Self.buttonSpacing
    }

    /// How much shorter the first line is than the others: the buttons reach this far into the text's width, plus
    /// the gap before them.
    private var toolbarReserve: CGFloat {
        Self.toolbarInset + Self.toolbarPadding.width + toolbarWidth + Self.toolbarGap - PopupLayout.contentInset
    }

    /// Puts the buttons at the height of the first line.
    private var toolbarTopInset: CGFloat {
        Self.verticalPadding + (lineHeight - Self.buttonSize.height) / 2 - Self.toolbarPadding.height
    }

    /// Widest the text may get so the whole popup stays within its maximum width.
    private var maxTextWidth: CGFloat {
        PopupLayout.maximumWidth - 2 * PopupLayout.contentInset
    }

    /// Tallest the text may get before it scrolls.
    private var maxTextHeight: CGFloat {
        max(model.maxHeight - 2 * Self.verticalPadding, 24)
    }
}

// MARK: - SizeReport

/// The content size tagged with the selection it belongs to, so every new selection reports once.
private struct SizeReport: Equatable, Sendable {
    var size: CGSize
    var generation: Int
}

// MARK: - ProposedWidthLayout

/// Lays out its content as if offered `width`, whatever it is offered itself: the content takes its natural size
/// up to that width, which is what the popup measures.
private struct ProposedWidthLayout: Layout {
    var width: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        subviews.first?.sizeThatFits(ProposedViewSize(width: width, height: nil)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: width, height: nil))
    }
}
