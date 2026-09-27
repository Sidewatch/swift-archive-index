//
//  ArchiveMethod.swift
//  ArchiveIndex
//
//  How a member's bytes are packed.
//
//  Created by David Sherlock on 9/24/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// How a member is packed inside its archive.
public enum ArchiveMethod: Sendable, Equatable {
    /// Bytes as they are (a tar member, a zip's method 0).
    case stored
    /// Raw DEFLATE (a zip's method 8) — what `ZipIndex.data(for:in:)` can unpack.
    case deflate
    /// A zip method this package does not unpack (bzip2, LZMA, zstd…), by its number.
    case other(Int)

    /// The method a zip header records by number: 0 stored, 8 DEFLATE, anything else by its number.
    init(zipMethod: Int) {
        switch zipMethod { case 0: self = .stored; case 8: self = .deflate; default: self = .other(zipMethod) }
    }
}
