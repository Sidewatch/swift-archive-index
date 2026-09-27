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
    /// The roots of the tree for `entries`.
    public static func build(_ entries: [ArchiveEntry]) -> [ArchiveNode] {
        let root = ArchiveNode(name: "", path: "", isDirectory: true, size: 0)
        var folders: [String: ArchiveNode] = ["": root]
        func folder(_ path: String) -> ArchiveNode {
            if let hit = folders[path] { return hit }
            let parts = path.split(separator: "/").map(String.init)
            let parent = folder(parts.dropLast().joined(separator: "/"))
            let node = ArchiveNode(name: parts.last ?? path, path: path, isDirectory: true, size: 0)
            parent.append(node)
            folders[path] = node
            return node
        }
        for entry in entries {
            let trimmed = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
            let parts = trimmed.split(separator: "/").map(String.init)
            guard !parts.isEmpty else { continue }
            if entry.isDirectory {
                _ = folder(parts.joined(separator: "/"))
            } else {
                let parent = folder(parts.dropLast().joined(separator: "/"))
                parent.append(ArchiveNode(name: parts.last!, path: entry.path, isDirectory: false, size: entry.size))
            }
        }
        root.settle()
        return root.children
    }
}
