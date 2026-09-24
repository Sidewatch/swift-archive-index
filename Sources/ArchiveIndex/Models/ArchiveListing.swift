//
//  ArchiveListing.swift
//  ArchiveIndex
//
//  An archive read: its kind, its members and their totals.
//
//  Created by David Sherlock on 9/24/26.
//

import Foundation

/// What `Archive.listing(at:)` answers: the format, every member, and the totals a summary line
/// wants. `tree` folds the members through `ArchiveTree`.
public struct ArchiveListing: Sendable {
    public let kind: ArchiveKind
    public let entries: [ArchiveEntry]

    public init(kind: ArchiveKind, entries: [ArchiveEntry]) { self.kind = kind; self.entries = entries }

    /// Members that are files.
    public var fileCount: Int { entries.lazy.filter { !$0.isDirectory }.count }
    /// Members listed as directories (folders a path merely implies are not counted).
    public var folderCount: Int { entries.lazy.filter { $0.isDirectory }.count }
    /// Every file's unpacked size, summed.
    public var totalSize: Int { entries.reduce(0) { $0 + ($1.isDirectory ? 0 : $1.size) } }
    /// The members folded into folders.
    public var tree: [ArchiveNode] { ArchiveTree.build(entries) }
}
