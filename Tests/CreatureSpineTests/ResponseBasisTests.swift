import Testing
@testable import CreatureSpine

@Suite struct ResponseBasisTests {
    @Test func codeFenceDetectorPreservesHistoricalBehaviour() {
        let d = CodeFenceBasisDetector()
        #expect(d.basis(of: "here is why") == .words)
        // A fenced response is the code phase, and its payload is the response untouched.
        #expect(d.basis(of: "```swift\nlet x = 1\n```") == .code("```swift\nlet x = 1\n```"))
    }

    @Test func codePayloadIsAccessible() {
        #expect(ResponseBasis.code("src").codePayload == "src")
        #expect(ResponseBasis.words.codePayload == nil)
    }
}
