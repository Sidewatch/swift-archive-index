//
//  ArchiveEntry.swift
//  ArchiveIndex
//
//  One member of an archive, as its directory describes it.
//
//  Created by David Sherlock on 9/24/26.
//

import Foundation

/// One member of an archive as its directory lists it — nothing here needed the member's bytes.
public struct ArchiveEntry: Sendable, Equatable {
    /// The path inside the archive, `/`-separated; a directory's ends in `/`.
    public let path: String
    /// The member's size once unpacked, in bytes (0 for a directory).
    public let size: Int
    /// The bytes the archive spends on it (equal to `size` when stored uncompressed).
    public let compressedSize: Int
    /// Whether the member is a directory.
    public let isDirectory: Bool
    /// The member's recorded modification time, when the archive carries one.
    public let modified: Date?
    /// How the member is packed.
    public let method: ArchiveMethod
    /// Where the member's data begins — for the zip, the local header's offset; for a tar, the
    /// first byte after the header block. A reader's own bookkeeping; not for callers.
    let offset: Int

    public init(path: String, size: Int, compressedSize: Int, isDirectory: Bool, modified: Date?, method: ArchiveMethod, offset: Int = 0) {
        self.path = path; self.size = size; self.compressedSize = compressedSize; self.isDirectory = isDirectory
        self.modified = modified; self.method = method; self.offset = offset
    }

    /// The last path component (a directory's without its trailing `/`).
    public var name: String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        return trimmed.split(separator: "/").last.map(String.init) ?? trimmed
    }
}
