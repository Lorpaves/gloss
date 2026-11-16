//
//  AboutSettingsView.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/16.
//

import SwiftUI
import AppKit

/// The About tab of Settings: what Gloss is, which version is running and where to find more.
internal struct AboutSettingsView: View {
    // MARK: - Properties

    internal var info: AppInfo
    /// Opens the licenses of the software shipped inside Gloss.
    internal var onShowNotices: () -> Void

    private static let iconSize: CGFloat = 72

    // MARK: - Body

    internal var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 28)
                .padding(.bottom, 4)
            Form {
                Section {
                    LabeledContent("官网") {
                        link("gloss.lorpaves.com", to: AppInfo.website)
                    }
                    LabeledContent("源代码") {
                        link("github.com/lorpaves/gloss", to: AppInfo.repository)
                    }
                    LabeledContent("问题反馈") {
                        link("GitHub Issues", to: AppInfo.issues)
                    }
                }
                Section {
                    LabeledContent("许可") {
                        HStack(spacing: 8) {
                            Text(verbatim: AppInfo.license)
                                .foregroundStyle(.secondary)
                            Button("第三方许可") {
                                onShowNotices()
                            }
                        }
                    }
                } footer: {
                    Text(verbatim: info.copyright)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
        }
    }

    // MARK: - Private

    private var header: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: Self.iconSize, height: Self.iconSize)
                .accessibilityHidden(true)
            Text(verbatim: "Gloss")
                .font(.title2.weight(.semibold))
                .padding(.top, 2)
            Text("在任意 App 中选中文字即可离线翻译。")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            versionLine
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    /// "Version 1.0.2 (3)": the word comes first in every language Gloss is localized in.
    private var versionLine: Text {
        Text("版本") + Text(verbatim: " \(info.version) (\(info.build))")
    }

    @ViewBuilder
    private func link(_ title: String, to address: String) -> some View {
        if let url = URL(string: address) {
            Link(title, destination: url)
        }
    }
}
