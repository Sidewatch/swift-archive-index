//
//  ArchiveKind.swift
//  ArchiveIndex
//
//  The formats a reader exists for.
//
//  Created by David Sherlock on 9/24/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// An archive format the package reads.
public enum ArchiveKind: String, Sendable, CaseIterable {
    /// A zip (and every zip-shaped container: jar, war, ipa, vsix, whl, nupkg, crx, epub…).
    case zip
    /// A POSIX / GNU tar, uncompressed.
    case tar

    /// The kind `head` (an archive's first bytes — at least 512 tell a tar apart) begins, or nil.
    public static func detect(head: Data) -> ArchiveKind? {
        if ZipIndex.isZip(head: head) { return .zip }
        if TarIndex.isTar(head: head) { return .tar }
        return nil
    }
}
