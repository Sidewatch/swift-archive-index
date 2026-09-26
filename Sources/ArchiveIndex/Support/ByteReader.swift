//
//  ByteReader.swift
//  ArchiveIndex
//
//  Little-endian integers and slices out of a Data, bounds-checked.
//
//  Created by David Sherlock on 9/24/26.
//

import Foundation

/// Bounds-checked little-endian reads over a `Data` — the zip format's numbers. Every read
/// returns nil past the end rather than trapping, so a truncated file is a refusal, never a crash.
struct ByteReader {
    let data: Data
    /// Reads are relative to the data's own start whatever its `startIndex` (a slice's is not 0).
    private var base: Int { data.startIndex }

    func u16(_ at: Int) -> Int? {
        guard at >= 0, at + 2 <= data.count else { return nil }
        return Int(data[base + at]) | Int(data[base + at + 1]) << 8
    }
    func u32(_ at: Int) -> Int? {
        guard at >= 0, at + 4 <= data.count else { return nil }
        return Int(data[base + at]) | Int(data[base + at + 1]) << 8 | Int(data[base + at + 2]) << 16 | Int(data[base + at + 3]) << 24
    }
    func u64(_ at: Int) -> Int? {
        guard at >= 0, at + 8 <= data.count, let lo = u32(at), let hi = u32(at + 4), hi < 1 << 31 else { return nil }
        return lo | hi << 32
    }
    func bytes(_ at: Int, _ count: Int) -> Data? {
        guard at >= 0, count >= 0, at + count <= data.count else { return nil }
        return data.subdata(in: (base + at)..<(base + at + count))
    }
}
