import Testing
import Foundation
@testable import CreatureTrunkSwift

@Suite struct SwiftSymbolGraphParserTests {
    
    /// The exact output from a real `swiftc` run on broken code.
    private static let brokenSymbolGraph = """
    {"metadata":{"formatVersion":{"major":0,"minor":6,"patch":0}},"module":{"name":"Broken","platform":{"architecture":"arm64","vendor":"apple","operatingSystem":{"name":"macosx","minimumVersion":{"major":26,"minor":0}}}},"symbols":[{"kind":{"identifier":"swift.func","displayName":"Function"},"identifier":{"precise":"s:6Broken6calleryyF","interfaceLanguage":"swift"},"pathComponents":["caller()"],"names":{"title":"caller()","subHeading":[{"kind":"keyword","spelling":"func"},{"kind":"text","spelling":" "},{"kind":"identifier","spelling":"caller"},{"kind":"text","spelling":"()"}]},"functionSignature":{"returns":[{"kind":"text","spelling":"()"}]},"declarationFragments":[{"kind":"keyword","spelling":"func"},{"kind":"text","spelling":" "},{"kind":"identifier","spelling":"caller"},{"kind":"text","spelling":"()"}],"accessLevel":"internal","location":{"uri":"file:///tmp/Broken.swift","position":{"line":0,"character":5}}}],"relationships":[]}
    """
    
    @Test func parsesBrokenCodeSymbolGraph() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sg-test-\(UUID().uuidString).symbols.json")
        try Self.brokenSymbolGraph.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        
        let symbols = SwiftSymbolGraphParser.parseSymbolGraph(at: tmp.path)
        #expect(symbols.count == 1)
        #expect(symbols[0].usr == "s:6Broken6calleryyF")
        #expect(symbols[0].name == "caller()")
        #expect(symbols[0].filePath == "/tmp/Broken.swift")
        #expect(symbols[0].line == 1)   // 0-based → 1-based
        #expect(symbols[0].character == 6) // 0-based → 1-based
    }
    
    @Test func spatialIndexFindsInnermostSymbol() {
        let symbols = [
            SwiftSymbolGraphParser.Symbol(usr: "s:Outer", name: "outer", filePath: "/a.swift", line: 1, character: 1),
            SwiftSymbolGraphParser.Symbol(usr: "s:Inner", name: "inner", filePath: "/a.swift", line: 5, character: 1),
        ]
        let index = SwiftSymbolGraphParser.SpatialIndex(symbols: symbols)
        #expect(index.usrFor(filePath: "/a.swift", line: 2) == "s:Outer")
        #expect(index.usrFor(filePath: "/a.swift", line: 6) == "s:Inner")
        #expect(index.usrFor(filePath: "/a.swift", line: 10) == "s:Inner")
        #expect(index.usrFor(filePath: "/missing.swift", line: 1) == nil)
    }
    
    @Test func parseMissingFileReturnsEmpty() {
        let symbols = SwiftSymbolGraphParser.parseSymbolGraph(at: "/nonexistent/foo.symbols.json")
        #expect(symbols.isEmpty)
    }
}
