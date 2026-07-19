import Testing
import Foundation
@testable import CreatureTrunk
import CreatureSpine

@Suite struct TrunkNodeTests {

    @Test func codableRoundTrip() throws {
        let coordinate = TrunkCoordinate(
            path: ["MyModule", "MyType", "myFunction"],
            kind: "function",
            truthKey: "abc123"
        )
        let node = TrunkNode(
            id: "MyModule/myFunction#swift",
            coordinate: coordinate,
            channels: [
                TrunkChannel(index: 0, language: "rosetta", content: "func myFunction/1"),
                TrunkChannel(index: 1, language: "swift", content: "func myFunction(x: Int) {}")
            ]
        )

        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(TrunkNode.self, from: data)

        #expect(decoded.id == node.id)
        #expect(decoded.coordinate == node.coordinate)
        #expect(decoded.channels == node.channels)
        #expect(decoded.truthChannel?.content == "func myFunction/1")
        #expect(decoded.channel(language: "swift")?.content == "func myFunction(x: Int) {}")
    }

    @Test func channelsAreSortedByIndex() {
        let node = TrunkNode(
            id: "n",
            coordinate: TrunkCoordinate(path: ["a"], kind: "function", truthKey: "k"),
            channels: [
                TrunkChannel(index: 1, language: "swift", content: "one"),
                TrunkChannel(index: 0, language: "rosetta", content: "zero")
            ]
        )
        #expect(node.channels.map(\.index) == [0, 1])
    }

    @Test func lookupByIndexAndLanguage() {
        let node = TrunkNode(
            id: "n",
            coordinate: TrunkCoordinate(path: ["a"], kind: "function", truthKey: "k"),
            channels: [
                TrunkChannel(index: 0, language: "rosetta", content: "skeleton"),
                TrunkChannel(index: 1, language: "python", content: "def f(): pass")
            ]
        )
        #expect(node.channel(at: 0)?.language == "rosetta")
        #expect(node.channel(at: 2) == nil)
        #expect(node.channel(language: "PYTHON")?.index == 1)
        #expect(node.channel(language: "swift") == nil)
    }
}

@Suite struct TrunkColourTests {

    @Test func channelZeroIsWhite() {
        let channel = TrunkChannel(index: 0, language: "rosetta", content: "skeleton")
        #expect(channel.colour.saturation == 0)
        #expect(channel.colour.value == 1)
    }

    @Test func distinctLanguagesGetDistinctChroma() {
        let swift = TrunkChannel(index: 1, language: "swift", content: "")
        let python = TrunkChannel(index: 1, language: "python", content: "")

        #expect(swift.colour.saturation > 0)
        #expect(python.colour.saturation > 0)
        #expect(swift.colour.hue != python.colour.hue)
    }

    @Test func sameLanguageIsDeterministic() {
        let a = TrunkColour.forLanguage("swift")
        let b = TrunkColour.forLanguage("swift")
        #expect(a == b)
    }

    @Test func languageNameIsCaseInsensitiveForColour() {
        let a = TrunkColour.forLanguage("Swift")
        let b = TrunkColour.forLanguage("swift")
        #expect(a == b)
    }
}

@Suite struct CodeTrunkTests {

    @Test func addAndLookupById() {
        var trunk = CodeTrunk()
        let node = TrunkNode(
            id: "node-1",
            coordinate: TrunkCoordinate(path: ["a", "b"], kind: "function", truthKey: "k1"),
            channels: [TrunkChannel(index: 0, language: "rosetta", content: "x")]
        )
        trunk.add(node)
        #expect(trunk.node(id: "node-1") != nil)
        #expect(trunk.node(id: "missing") == nil)
    }

    @Test func lookupByPath() {
        var trunk = CodeTrunk()
        let node = TrunkNode(
            id: "node-1",
            coordinate: TrunkCoordinate(path: ["a", "b"], kind: "function", truthKey: "k1"),
            channels: []
        )
        trunk.add(node)
        #expect(trunk.nodes(path: ["a", "b"]).count == 1)
        #expect(trunk.nodes(pathKey: "a.b").count == 1)
        #expect(trunk.nodes(path: ["x"]).isEmpty)
    }

    @Test func nodesSharingTruthKeyLinksAcrossLanguages() {
        var trunk = CodeTrunk()
        let coordA = TrunkCoordinate(path: ["a"], kind: "function", truthKey: "shared")
        let coordB = TrunkCoordinate(path: ["b"], kind: "function", truthKey: "shared")
        let coordC = TrunkCoordinate(path: ["c"], kind: "function", truthKey: "different")

        trunk.add(TrunkNode(id: "1", coordinate: coordA, channels: []))
        trunk.add(TrunkNode(id: "2", coordinate: coordB, channels: []))
        trunk.add(TrunkNode(id: "3", coordinate: coordC, channels: []))

        let shared = trunk.nodesSharing(truthKey: "shared")
        #expect(shared.count == 2)
        #expect(Set(shared.map(\.id)) == Set(["1", "2"]))
    }

    @Test func codableRoundTrip() throws {
        var trunk = CodeTrunk()
        trunk.add(TrunkNode(
            id: "1",
            coordinate: TrunkCoordinate(path: ["a"], kind: "function", truthKey: "k"),
            channels: [TrunkChannel(index: 0, language: "rosetta", content: "skeleton")]
        ))
        let data = try JSONEncoder().encode(trunk)
        let decoded = try JSONDecoder().decode(CodeTrunk.self, from: data)
        #expect(decoded.nodes.count == 1)
        #expect(decoded.node(id: "1")?.coordinate.truthKey == "k")
    }
}
