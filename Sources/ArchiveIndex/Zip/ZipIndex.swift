//
//  ZipIndex.swift
//  ArchiveIndex
//
//  A zip's central directory, read without unpacking anything; one member unpacked on demand.
//
//  Created by David Sherlock on 9/24/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A zip archive as its CENTRAL DIRECTORY describes it (APPNOTE 4.3): the end-of-central-
/// directory record is found from the file's tail, the directory it points at is walked once,
/// and each header gives a member's path, sizes, method and time — no member is unpacked to list
/// them. ZIP64 (the 0xFFFF / 0xFFFFFFFF markers with the extra field and the 64-bit end record)
/// is read; spanned archives are not. `data(for:in:)` unpacks ONE member: stored bytes as they
/// are, DEFLATE through Compression's raw-inflate; anything else is refused by name.
public enum ZipIndex {
    /// Record signatures (`PK\3\4`, `PK\1\2`, `PK\5\6`, and the ZIP64 locator and end record),
    /// read as little-endian 32-bit numbers.
    static let localSignature = 0x0403_4B50, centralSignature = 0x0201_4B50
    static let endSignature = 0x0605_4B50, end64LocatorSignature = 0x0706_4B50, end64Signature = 0x0606_4B50
    /// The end record's fixed size, and how far its trailing comment can push it from the tail.
    static let endRecordSize = 22, maxCommentLength = 0xFFFF

    /// Whether `head` (the file's first bytes) begins a zip: a local header, or the end record of
    /// an empty archive.
    public static func isZip(head: Data) -> Bool {
        guard head.count >= 4 else { return false }
        let sig = ByteReader(data: head).u32(0)
        return sig == localSignature || sig == endSignature
    }

    /// The archive's members, in directory order.
    public static func entries(at url: URL) throws -> [ArchiveEntry] {
        try entries(in: try mapped(url))
    }

    /// The archive's members from the archive's bytes.
    public static func entries(in data: Data) throws -> [ArchiveEntry] {
        let r = ByteReader(data: data)
        guard let end = endRecordOffset(r) else { throw ArchiveError.notAnArchive }
        let directory = try directoryLocation(r, endRecord: end)
        var out: [ArchiveEntry] = []
        out.reserveCapacity(directory.count)
        var pos = directory.offset
        for _ in 0..<directory.count {
            guard let entry = header(r, at: &pos) else { throw ArchiveError.truncated }
            out.append(entry)
        }
        return out
    }

    /// One member's unpacked bytes.
    public static func data(for entry: ArchiveEntry, in url: URL) throws -> Data {
        try data(for: entry, in: try mapped(url))
    }

    /// One member's unpacked bytes out of the archive's bytes.
    public static func data(for entry: ArchiveEntry, in data: Data) throws -> Data {
        let r = ByteReader(data: data)
        guard r.u32(entry.offset) == localSignature, let flags = r.u16(entry.offset + 6),
            let nameLength = r.u16(entry.offset + 26), let extraLength = r.u16(entry.offset + 28)
        else { throw ArchiveError.truncated }
        if flags & 1 != 0 { throw ArchiveError.encrypted }
        let start = entry.offset + 30 + nameLength + extraLength
        guard let raw = r.bytes(start, entry.compressedSize) else { throw ArchiveError.truncated }
        switch entry.method {
        case .stored: return raw
        case .deflate:
            if entry.compressedSize == 0 { return Data() }
            guard let inflated = try? (raw as NSData).decompressed(using: .zlib) as Data, inflated.count == entry.size else {
                throw ArchiveError.corruptMember
            }
            return inflated
        case .other(let m): throw ArchiveError.unsupportedMethod(m)
        }
    }

    // MARK: - The directory

    /// The file's bytes, memory-mapped when safe; any read failure is `notAnArchive`.
    static func mapped(_ url: URL) throws -> Data {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { throw ArchiveError.notAnArchive }
        return data
    }

    /// Where the end-of-central-directory record starts: the last `PK\5\6` within the comment's
    /// reach of the tail.
    static func endRecordOffset(_ r: ByteReader) -> Int? {
        let count = r.data.count
        guard count >= endRecordSize else { return nil }
        let floor = max(0, count - endRecordSize - maxCommentLength)
        var pos = count - endRecordSize
        while pos >= floor {
            if r.u32(pos) == endSignature, let comment = r.u16(pos + 20), pos + endRecordSize + comment == count { return pos }
            pos -= 1
        }
        return nil
    }

    /// The central directory's offset and entry count, from the end record or — when it carries
    /// the ZIP64 markers — from the 64-bit end record its locator names.
    static func directoryLocation(_ r: ByteReader, endRecord end: Int) throws -> (offset: Int, count: Int) {
        guard let count16 = r.u16(end + 10), let size32 = r.u32(end + 12), let offset32 = r.u32(end + 16) else {
            throw ArchiveError.truncated
        }
        if count16 != 0xFFFF, size32 != 0xFFFF_FFFF, offset32 != 0xFFFF_FFFF { return (offset32, count16) }
        let locator = end - 20
        guard r.u32(locator) == end64LocatorSignature, let end64 = r.u64(locator + 8), r.u32(end64) == end64Signature,
            let count = r.u64(end64 + 32), let offset = r.u64(end64 + 48)
        else { throw ArchiveError.notAnArchive }
        return (offset, count)
    }

    /// One central-directory header at `pos`, advancing `pos` past it.
    static func header(_ r: ByteReader, at pos: inout Int) -> ArchiveEntry? {
        guard r.u32(pos) == centralSignature, let flags = r.u16(pos + 8), let method = r.u16(pos + 10),
            let time = r.u16(pos + 12), let date = r.u16(pos + 14), let comp32 = r.u32(pos + 20), let size32 = r.u32(pos + 24),
            let nameLength = r.u16(pos + 28), let extraLength = r.u16(pos + 30), let commentLength = r.u16(pos + 32),
            let attributes = r.u32(pos + 38), let local32 = r.u32(pos + 42),
            let nameBytes = r.bytes(pos + 46, nameLength), let extra = r.bytes(pos + 46 + nameLength, extraLength)
        else { return nil }
        var size = size32, comp = comp32, local = local32
        if size32 == 0xFFFF_FFFF || comp32 == 0xFFFF_FFFF || local32 == 0xFFFF_FFFF {
            let wide = zip64Fields(
                extra, wantSize: size32 == 0xFFFF_FFFF, wantComp: comp32 == 0xFFFF_FFFF, wantLocal: local32 == 0xFFFF_FFFF)
            size = wide.size ?? size; comp = wide.comp ?? comp; local = wide.local ?? local
        }
        let name =
            (flags & 0x800 != 0 ? String(data: nameBytes, encoding: .utf8) : nil)
            ?? String(data: nameBytes, encoding: .utf8) ?? String(data: nameBytes, encoding: .isoLatin1) ?? ""
        let isDirectory = name.hasSuffix("/") || (attributes & 0x10 != 0 && size == 0)
        pos += 46 + nameLength + extraLength + commentLength
        return ArchiveEntry(
            path: name, size: size, compressedSize: comp, isDirectory: isDirectory,
            modified: dosDate(date: date, time: time), method: ArchiveMethod(zipMethod: method), offset: local)
    }

    /// The 64-bit values in a header's ZIP64 extra field (id 1), present only for the fields the
    /// 32-bit header marked, in the order size, compressed size, local header offset.
    static func zip64Fields(_ extra: Data, wantSize: Bool, wantComp: Bool, wantLocal: Bool) -> (size: Int?, comp: Int?, local: Int?) {
        let r = ByteReader(data: extra)
        var pos = 0
        while let id = r.u16(pos), let length = r.u16(pos + 2) {
            if id == 1 {
                var at = pos + 4
                var size: Int?, comp: Int?, local: Int?
                if wantSize { size = r.u64(at); at += 8 }
                if wantComp { comp = r.u64(at); at += 8 }
                if wantLocal { local = r.u64(at) }
                return (size, comp, local)
            }
            pos += 4 + length
        }
        return (nil, nil, nil)
    }

    /// A DOS date and time pair as a Date in the local calendar; nil for the zero value.
    static func dosDate(date: Int, time: Int) -> Date? {
        guard date != 0 else { return nil }
        var c = DateComponents()
        c.year = 1980 + (date >> 9); c.month = (date >> 5) & 0xF; c.day = date & 0x1F
        c.hour = time >> 11; c.minute = (time >> 5) & 0x3F; c.second = (time & 0x1F) * 2
        return Calendar.current.date(from: c)
    }
}
