//
//  ArchiveTree.swift
//  ArchiveIndex
//
//  Flat entry paths folded into folders.
//
//  Created by David Sherlock on 9/24/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Folds an archive's flat entries into a tree: intermediate folders a file path implies are
/// created whether or not the archive lists them, folders come before files, each group in
/// Finder's order, and a folder's size is what lies beneath it.
public enum ArchiveTree {
    /// The deepest a path is folded. A member's path is the archive's word and may name tens of
    /// thousands of levels; past the limit the rest of the path is one name, so walking the tree
    /// never goes deeper than this.
    public static let depthLimit = 256

    /// `path` as folder levels, the levels past ``depthLimit`` kept together as the last one.
    static func levels(of path: String) -> [String] {
        let parts = path.split(separator: "/", maxSplits: depthLimit - 1, omittingEmptySubsequences: true).map(String.init)
        guard parts.count == depthLimit, let last = parts.last else { return parts }
        return parts.dropLast() + [last.trimmingCharacters(in: CharacterSet(charactersIn: "/"))]
    }

    /// The roots of the tree for `entries`.
    public static func build(_ entries: [ArchiveEntry]) -> [ArchiveNode] {
        let root = ArchiveNode(name: "", path: "", isDirectory: true, size: 0)
        var folders: [String: ArchiveNode] = ["": root]
        /// The folder at `parts`, made with every folder above it that is not there yet.
        func folder(_ parts: ArraySlice<String>) -> ArchiveNode {
            var node = root
            var path = ""
            for part in parts {
                path = path.isEmpty ? part : path + "/" + part
                if let hit = folders[path] { node = hit; continue }
                let made = ArchiveNode(name: part, path: path, isDirectory: true, size: 0)
                node.append(made)
                folders[path] = made
                node = made
            }
            return node
        }
        for entry in entries {
            let trimmed = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
            let parts = levels(of: trimmed)
            guard !parts.isEmpty else { continue }
            if entry.isDirectory {
                _ = folder(parts[...])
            } else {
                let parent = folder(parts.dropLast())
                parent.append(ArchiveNode(name: parts.last!, path: entry.path, isDirectory: false, size: entry.size))
            }
        }
        root.settle()
        return root.children
    }
}
