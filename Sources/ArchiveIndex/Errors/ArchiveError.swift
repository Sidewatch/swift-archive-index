//
//  ArchiveError.swift
//  ArchiveIndex
//
//  What reading an archive can refuse.
//
//  Created by David Sherlock on 9/24/26.
//

import Foundation

/// Why an archive, or a member of one, could not be read.
public enum ArchiveError: Error, Equatable, Sendable {
    /// The file is not a zip / tar, or its directory is missing or corrupt.
    case notAnArchive
    /// The directory points past the end of the file.
    case truncated
    /// The member is packed with a method this package does not unpack.
    case unsupportedMethod(Int)
    /// The member is encrypted.
    case encrypted
    /// The member's unpacked bytes could not be produced (a corrupt DEFLATE stream).
    case corruptMember
}
