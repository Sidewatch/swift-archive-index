//
//  TarIndex.swift
//  ArchiveIndex
//
//  A tar's headers walked block by block; one member's bytes are a slice.
//
//  Created by David Sherlock on 9/24/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// An uncompressed tar as its 512-byte headers describe it: ustar (name + prefix), pax
/// (`path` and `size` records from an `x` header apply to the next member), GNU long names
/// (`L`), old v7 (no magic, a valid checksum). Members other than files and directories
/// (links, devices, the pax global header) are walked over and not listed. A member's bytes are
/// a slice at its offset — `data(for:in:)` never decompresses, because a tar never compresses.
public enum TarIndex {
    /// A tar header, and every member's data, occupies whole blocks of this many bytes.
    static let blockSize = 512

    /// Whether `head` (the file's first 512 bytes) is a tar header block.
    public static func isTar(head: Data) -> Bool {
        guard head.count >= blockSize else { return false }
        return checksumValid(head, at: 0) && (magic(head, at: 0) || nameField(head, at: 0) != nil)
    }

    /// The archive's members, in order.
    public static func entries(at url: URL) throws -> [ArchiveEntry] {
        try entries(in: try ZipIndex.mapped(url))
    }

    /// The archive's members from the archive's bytes.
    public static func entries(in data: Data) throws -> [ArchiveEntry] {
        guard isTar(head: data.prefix(blockSize)) else { throw ArchiveError.notAnArchive }
        var out: [ArchiveEntry] = []
        var pos = 0
        var longName: String?, paxSize: Int?
        while pos + blockSize <= data.count {
            let block = data.subdata(in: (data.startIndex + pos)..<(data.startIndex + pos + blockSize))
            if block.allSatisfy({ $0 == 0 }) { break }
            guard checksumValid(block, at: 0), let name = nameField(block, at: 0) else { throw ArchiveError.notAnArchive }
            let size = paxSize ?? sizeField(block)
            let dataStart = pos + blockSize
            let type = block[block.startIndex + 156]
            let next = dataStart + (size + blockSize - 1) / blockSize * blockSize
            switch type {
            case UInt8(ascii: "L"):
                longName = string(data.subdata(in: (data.startIndex + dataStart)..<min(data.endIndex, data.startIndex + dataStart + size)))
            case UInt8(ascii: "x"):
                let records = paxRecords(data.subdata(in: (data.startIndex + dataStart)..<min(data.endIndex, data.startIndex + dataStart + size)))
                if let p = records["path"] { longName = p }
                if let s = records["size"].flatMap(Int.init) { paxSize = s }
            case 0, UInt8(ascii: "0"), UInt8(ascii: "7"), UInt8(ascii: "5"):
                guard dataStart + size <= data.count else { throw ArchiveError.truncated }
                let path = longName ?? name
                let isDirectory = type == UInt8(ascii: "5") || path.hasSuffix("/")
                out.append(ArchiveEntry(path: isDirectory && !path.hasSuffix("/") ? path + "/" : path, size: isDirectory ? 0 : size,
                                        compressedSize: isDirectory ? 0 : size, isDirectory: isDirectory,
                                        modified: mtimeField(block), method: .stored, offset: dataStart))
                longName = nil; paxSize = nil
            default:
                longName = nil; paxSize = nil
            }
            pos = next
        }
        return out
    }

    /// One member's bytes.
    public static func data(for entry: ArchiveEntry, in url: URL) throws -> Data {
        try data(for: entry, in: try ZipIndex.mapped(url))
    }

    /// One member's bytes out of the archive's bytes.
    public static func data(for entry: ArchiveEntry, in data: Data) throws -> Data {
        guard let slice = ByteReader(data: data).bytes(entry.offset, entry.size) else { throw ArchiveError.truncated }
        return slice
    }

    // MARK: - Fields

    /// `length` bytes at `at` in a header block.
    static func field(_ block: Data, _ at: Int, _ length: Int) -> Data {
        block.subdata(in: (block.startIndex + at)..<(block.startIndex + at + length))
    }
    /// A NUL-terminated header string: UTF-8, else Latin-1.
    static func string(_ d: Data) -> String {
        let cut = d.prefix { $0 != 0 }
        return String(data: cut, encoding: .utf8) ?? String(data: cut, encoding: .isoLatin1) ?? ""
    }
    /// A numeric header field: ASCII octal, or GNU base-256 when the high bit is set.
    static func octal(_ d: Data) -> Int? {
        if let first = d.first, first & 0x80 != 0 {   // base-256 (GNU) for sizes past 8 GB
            return d.dropFirst().reduce(Int(first & 0x7F)) { $0 << 8 | Int($1) }
        }
        let text = string(d).trimmingCharacters(in: CharacterSet(charactersIn: " \0"))
        return Int(text, radix: 8)
    }
    /// Whether the header block carries the `ustar` magic.
    static func magic(_ block: Data, at: Int) -> Bool { String(decoding: field(block, at + 257, 5), as: UTF8.self) == "ustar" }
    /// The member's name, joined to the ustar `prefix` field when there is one; nil when empty.
    static func nameField(_ block: Data, at: Int) -> String? {
        let name = string(field(block, at, 100))
        guard !name.isEmpty else { return nil }
        let prefix = magic(block, at: at) ? string(field(block, at + 345, 155)) : ""
        return prefix.isEmpty ? name : prefix + "/" + name
    }
    /// The member's data size in bytes.
    static func sizeField(_ block: Data) -> Int { octal(field(block, 124, 12)) ?? 0 }
    /// The member's modification time (seconds since 1970).
    static func mtimeField(_ block: Data) -> Date? { octal(field(block, 136, 12)).map { Date(timeIntervalSince1970: TimeInterval($0)) } }
    /// Whether the header sums to its recorded checksum, the checksum field itself counted as
    /// spaces — the only test an old v7 header (no magic) can pass.
    static func checksumValid(_ block: Data, at: Int) -> Bool {
        guard let want = octal(field(block, at + 148, 8)) else { return false }
        var sum = 0
        for i in 0..<blockSize { sum += (148..<156).contains(i) ? 0x20 : Int(block[block.startIndex + at + i]) }
        return sum == want
    }
    /// The `length key=value\n` records of a pax header.
    static func paxRecords(_ d: Data) -> [String: String] {
        var out: [String: String] = [:]
        for line in string(d).split(separator: "\n") {
            guard let space = line.firstIndex(of: " "), let eq = line[space...].firstIndex(of: "=") else { continue }
            out[String(line[line.index(after: space)..<eq])] = String(line[line.index(after: eq)...])
        }
        return out
    }
}
