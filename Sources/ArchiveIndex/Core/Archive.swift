//
//  Archive.swift
//  ArchiveIndex
//
//  One entry: a file's format by its bytes, its listing, one member's data.
//
//  Created by David Sherlock on 9/24/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The one entry for a caller that has a file and does not know its format: `kind(at:)` reads
/// the first block, `listing(at:)` lists through the matching reader, `data(for:in:)` unpacks one
/// member. A name says nothing here — a `.jar` is a zip, a `.tar` named `.bin` is a tar.
public enum Archive {
    /// The format the file at `url` begins with, by its first 512 bytes, or nil.
    public static func kind(at url: URL) -> ArchiveKind? {
        guard let handle = try? FileHandle(forReadingFrom: url), let head = try? handle.read(upToCount: TarIndex.blockSize) else {
            return nil
        }
        return ArchiveKind.detect(head: head)
    }

    /// The archive at `url`, listed.
    public static func listing(at url: URL) throws -> ArchiveListing {
        guard let kind = kind(at: url) else { throw ArchiveError.notAnArchive }
        switch kind {
        case .zip: return ArchiveListing(kind: .zip, entries: try ZipIndex.entries(at: url))
        case .tar: return ArchiveListing(kind: .tar, entries: try TarIndex.entries(at: url))
        }
    }

    /// One member of the archive at `url`, unpacked.
    public static func data(for entry: ArchiveEntry, kind: ArchiveKind, in url: URL) throws -> Data {
        switch kind {
        case .zip: return try ZipIndex.data(for: entry, in: url)
        case .tar: return try TarIndex.data(for: entry, in: url)
        }
    }
}
