import Foundation

/// Letter-data reference encoding. The snippet library addresses everything in
/// LETTER DATA (the natural-English alphabet), never integers and never spatial
/// coordinates. A stable non-negative index is encoded to a lowercase bijective
/// base-26 string: 0→"a", 25→"z", 26→"aa", 27→"ab", …  Deterministic, pure letters,
/// compact, and plain Unicode text — so emoji may be layered on top freely. IP-clean.
public enum LetterKey {
    /// Encode a non-negative index to a lowercase base-26 letter key.
    public static func encode(_ index: Int) -> String {
        precondition(index >= 0, "LetterKey index must be non-negative")
        var n = index + 1               // bijective (1-indexed): no empty / leading-'a' ambiguity
        var s = ""
        while n > 0 {
            n -= 1
            s = String(UnicodeScalar(UInt8(97 + n % 26))) + s   // 'a' == 97
            n /= 26
        }
        return s
    }

    /// Decode a letter key back to its index (inverse of `encode`). `nil` if the key
    /// is empty or contains anything other than lowercase a–z.
    public static func decode(_ key: String) -> Int? {
        guard !key.isEmpty else { return nil }
        var n = 0
        for ch in key.unicodeScalars {
            guard ch.value >= 97, ch.value <= 122 else { return nil }
            n = n * 26 + Int(ch.value - 97) + 1
        }
        return n - 1
    }
}
