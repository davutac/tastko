// Ported from Hex (github.com/anomalyco/hex, revision 9338afc,
// ios/HEXShared/Spelling/HexWordList.swift). MIT license: see
// Resources/TypingModel/LICENSE-hex.txt and SOURCE-hex.md.

import Darwin
import Foundation

// MARK: - HexWordList
/// One of Hex's sorted word lists beside a language's typing model, such as `de.capitals`: one
/// lowercase NFC spelling per line, alone or followed by a tab and a number, sorted by its UTF-8
/// bytes, newline-terminated. The file is memory-mapped read-only, like the `.hextm` models, and
/// searched in place by bisection, so a lookup costs only the clean pages it touches.
nonisolated final class HexWordList: @unchecked Sendable {
    let byteCount: Int
    private let base: UnsafePointer<UInt8>

    // MARK: - Loading
    init?(url: URL) {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_size > 0 else { return nil }
        let size = Int(info.st_size)
        guard let mapped = mmap(nil, size, PROT_READ, MAP_PRIVATE, fd, 0), mapped != MAP_FAILED
        else { return nil }
        let bytes = UnsafePointer(mapped.assumingMemoryBound(to: UInt8.self))
        guard bytes[size - 1] == 10 else {
            munmap(mapped, size)
            return nil
        }
        base = bytes
        byteCount = size
    }

    deinit {
        munmap(UnsafeMutableRawPointer(mutating: base), byteCount)
    }

    // MARK: - Lookup
    /// Whether the list has `word` (lowercase NFC, as the builder writes them).
    func contains(_ word: String) -> Bool {
        line(of: word) != nil
    }

    /// The number after `word`'s tab, or nil when the list lacks the word or its line has none.
    func value(of word: String) -> Int? {
        guard let (end, next) = line(of: word), end < next else { return nil }
        var value = 0
        for i in (end + 1)..<next {
            let digit = Int(base[i]) - 48
            guard (0...9).contains(digit) else { return nil }
            value = value * 10 + digit
        }
        return value
    }

    // MARK: - Bisection
    /// Where `word`'s line ends (its tab or newline) and where its newline is.
    private func line(of word: String) -> (end: Int, next: Int)? {
        var word = word
        return word.withUTF8 { key -> (Int, Int)? in
            guard !key.isEmpty else { return nil }
            var lo = 0
            var hi = byteCount
            while lo < hi {
                // The line holding the middle byte: back to its start, on to its tab or newline.
                var start = (lo + hi) / 2
                while start > lo, base[start - 1] != 10 { start -= 1 }
                var end = start
                while base[end] != 10, base[end] != 9 { end += 1 }
                var next = end
                while base[next] != 10 { next += 1 }
                var order = 0
                var k = 0
                while order == 0, k < key.count, start + k < end {
                    order = Int(base[start + k]) - Int(key[k])
                    k += 1
                }
                if order == 0 { order = (end - start) - key.count }
                if order == 0 { return (end, next) }
                if order < 0 {
                    lo = next + 1
                }
                else {
                    hi = start
                }
            }
            return nil
        }
    }
}
