//
//  ByteReader.swift
//  ArchiveIndex
//
//  Little-endian integers and slices out of a Data, bounds-checked.
//
//  Created by David Sherlock on 9/24/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Bounds-checked little-endian reads over a `Data` — the zip format's numbers. Every read
/// returns nil past the end rather than trapping, so a truncated file is a refusal, never a crash.
struct ByteReader {
    /// The bytes read, any slice of a larger `Data`.
    let data: Data
    /// Reads are relative to the data's own start whatever its `startIndex` (a slice's is not 0).
    private var base: Int { data.startIndex }

    /// The little-endian 16-bit number at `at`.
    func u16(_ at: Int) -> Int? {
        guard at >= 0, at <= data.count - 2 else { return nil }
        return Int(data[base + at]) | Int(data[base + at + 1]) << 8
    }
    /// The little-endian 32-bit number at `at`.
    func u32(_ at: Int) -> Int? {
        guard at >= 0, at <= data.count - 4 else { return nil }
        return Int(data[base + at]) | Int(data[base + at + 1]) << 8 | Int(data[base + at + 2]) << 16 | Int(data[base + at + 3]) << 24
    }
    /// The little-endian 64-bit number at `at`; nil past 2^48, which no archive's offset, size or
    /// count reaches and which leaves every sum of a few of them far inside an `Int`.
    func u64(_ at: Int) -> Int? {
        guard at >= 0, at <= data.count - 8, let lo = u32(at), let hi = u32(at + 4), hi < 1 << 16 else { return nil }
        return lo | hi << 32
    }
    /// `count` bytes starting at `at`, copied out.
    func bytes(_ at: Int, _ count: Int) -> Data? {
        guard at >= 0, count >= 0, at <= data.count, count <= data.count - at else { return nil }
        return data.subdata(in: (base + at)..<(base + at + count))
    }
}

extension Int {
    /// The sum, held at `Int.max` instead of trapping: sizes an archive declares are added up
    /// as written, and enough of them overflow.
    func addingSaturated(_ other: Int) -> Int {
        let (sum, overflow) = addingReportingOverflow(other)
        return overflow ? (other < 0 ? .min : .max) : sum
    }
}
