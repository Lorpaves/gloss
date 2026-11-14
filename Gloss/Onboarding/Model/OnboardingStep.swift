//
//  OnboardingStep.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/14.
//

import Foundation

/// A page of the welcome guide.
internal enum OnboardingStep: Equatable, Sendable {
    case welcome
    /// Turning on Accessibility, which reading selections needs.
    case accessibility
    /// Allowing clipboard reads, which the copy fallback needs.
    case clipboard
    /// Downloading the translation model.
    case model
    case finish
}
