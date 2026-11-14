//
//  ModelDownloadError.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/14.
//

import Foundation

/// Errors of downloading the translation model, besides those of the network and the file system.
internal enum ModelDownloadError: Error, Equatable, Sendable {
    /// The server answered with this HTTP status.
    case httpStatus(Int)
    /// The server didn't continue where the partial file ends.
    case unexpectedRange
    /// The server has nothing past the partial file's end, so the partial file isn't part of this file.
    case rangeNotSatisfiable
    /// The downloaded file doesn't match its SHA-256 digest.
    case checksumMismatch
    /// The disk doesn't have room for the rest of the model.
    case insufficientSpace
}
