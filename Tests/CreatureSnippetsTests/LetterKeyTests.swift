import Testing
@testable import CreatureSnippets

@Suite struct LetterKeyTests {
    @Test func encodesBaseTwentySixLowercase() {
        #expect(LetterKey.encode(0) == "a")
        #expect(LetterKey.encode(25) == "z")
        #expect(LetterKey.encode(26) == "aa")
        #expect(LetterKey.encode(27) == "ab")
        #expect(LetterKey.encode(701) == "zz")
        #expect(LetterKey.encode(702) == "aaa")
    }

    @Test func roundTripsForAWideRange() {
        for n in stride(from: 0, to: 20_000, by: 7) {
            #expect(LetterKey.decode(LetterKey.encode(n)) == n)
        }
    }

    @Test func keysAreLowercaseLettersOnly() {
        for n in [0, 1, 25, 26, 999, 12345] {
            let key = LetterKey.encode(n)
            #expect(!key.isEmpty)
            #expect(key.unicodeScalars.allSatisfy { $0.value >= 97 && $0.value <= 122 })
        }
    }

    @Test func decodeRejectsNonLetters() {
        #expect(LetterKey.decode("") == nil)
        #expect(LetterKey.decode("a1") == nil)
        #expect(LetterKey.decode("A") == nil)     // uppercase not allowed
    }
}
