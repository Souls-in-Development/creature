import Testing
import Foundation
@testable import CreatureTrunk

@Suite struct TrunkStatusTests {

    @Test func orderingRedIsWorst() {
        #expect(TrunkStatus.green < TrunkStatus.yellow)
        #expect(TrunkStatus.yellow < TrunkStatus.red)
        #expect(TrunkStatus.green < TrunkStatus.red)
    }

    @Test func worstOfPair() {
        #expect(TrunkStatus.worst(.green, .red) == .red)
        #expect(TrunkStatus.worst(.yellow, .green) == .yellow)
        #expect(TrunkStatus.worst(.red, .red) == .red)
    }

    @Test func worstOfSequence() {
        #expect(TrunkStatus.worst(of: [.green, .green, .yellow]) == .yellow)
        #expect(TrunkStatus.worst(of: [.green, .red, .yellow]) == .red)
        // An empty set was never checked — it cannot be certified.
        #expect(TrunkStatus.worst(of: []) == .unknown)
    }

    @Test func codableRoundTrip() throws {
        for status in TrunkStatus.allCases {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(TrunkStatus.self, from: data)
            #expect(decoded == status)
        }
    }
}

@Suite struct TrunkAtlasTests {

    /// Builds a small trunk: a module containing a type containing a
    /// function, i.e. path depths 1 / 2 / 3 — enough to exercise real
    /// ancestor/descendant roll-up.
    private func makeTrunk() -> (trunk: CodeTrunk, moduleID: String, typeID: String, funcID: String) {
        var trunk = CodeTrunk()

        let moduleCoord = TrunkCoordinate(path: ["Demo"], kind: "module", truthKey: "module")
        let typeCoord = TrunkCoordinate(path: ["Demo", "Greeter"], kind: "struct", truthKey: "type")
        let funcCoord = TrunkCoordinate(path: ["Demo", "Greeter", "hello"], kind: "func", truthKey: "func")

        let moduleID = "module-1"
        let typeID = "type-1"
        let funcID = "func-1"

        trunk.add(TrunkNode(id: moduleID, coordinate: moduleCoord, channels: []))
        trunk.add(TrunkNode(id: typeID, coordinate: typeCoord, channels: []))
        trunk.add(TrunkNode(id: funcID, coordinate: funcCoord, channels: []))

        return (trunk, moduleID, typeID, funcID)
    }

    @Test func nodeAbsentFromMapIsUnknownNotGreen() {
        let (trunk, moduleID, _, _) = makeTrunk()
        let atlas = TrunkAtlas(trunk: trunk, leafStatus: [:])
        // Absence is not evidence of health.
        #expect(atlas.ownStatus(for: moduleID) == .unknown)
        #expect(atlas.ownStatus(for: moduleID) != .green)
    }

    @Test func containerWithOnlyRedChildRollsUpToRed() {
        let (trunk, moduleID, typeID, funcID) = makeTrunk()
        // Only the leaf function is red; module and type carry explicit green.
        let atlas = TrunkAtlas(trunk: trunk, leafStatus: [funcID: .red, typeID: .green, moduleID: .green])

        #expect(atlas.ownStatus(for: funcID) == .red)
        #expect(atlas.ownStatus(for: typeID) == .green)
        #expect(atlas.ownStatus(for: moduleID) == .green)

        // But the rolled-up status of every ancestor is red because the
        // function is nested beneath them.
        #expect(atlas.status(for: funcID) == .red)
        #expect(atlas.status(for: typeID) == .red)
        #expect(atlas.status(for: moduleID) == .red)
    }

    @Test func allGreenTrunkIsGreenOverall() {
        let (trunk, moduleID, typeID, funcID) = makeTrunk()
        let atlas = TrunkAtlas(trunk: trunk, leafStatus: [moduleID: .green, typeID: .green, funcID: .green])
        #expect(atlas.overall == .green)
    }

    @Test func overallReflectsWorstNode() {
        let (trunk, moduleID, typeID, funcID) = makeTrunk()
        let atlas = TrunkAtlas(trunk: trunk, leafStatus: [funcID: .red, typeID: .yellow, moduleID: .green])

        #expect(atlas.overall == .red)
        #expect(atlas.ownStatus(for: moduleID) == .green)
    }

    @Test func siblingRedDoesNotLeakToUnrelatedContainer() {
        var trunk = CodeTrunk()
        let coordA = TrunkCoordinate(path: ["Demo", "A"], kind: "struct", truthKey: "a")
        let coordAFunc = TrunkCoordinate(path: ["Demo", "A", "f"], kind: "func", truthKey: "af")
        let coordB = TrunkCoordinate(path: ["Demo", "B"], kind: "struct", truthKey: "b")

        trunk.add(TrunkNode(id: "a", coordinate: coordA, channels: []))
        trunk.add(TrunkNode(id: "a.f", coordinate: coordAFunc, channels: []))
        trunk.add(TrunkNode(id: "b", coordinate: coordB, channels: []))

        let atlas = TrunkAtlas(trunk: trunk, leafStatus: ["a.f": .red, "a": .green, "b": .green])

        #expect(atlas.status(for: "a") == .red)
        // "B" is a sibling of "A", not a descendant — must stay green.
        #expect(atlas.status(for: "b") == .green)
        #expect(atlas.overall == .red)
    }

    @Test func leafNodeWithNoDescendantsReflectsOnlyItsOwnStatus() {
        let (trunk, _, _, funcID) = makeTrunk()
        let atlas = TrunkAtlas(trunk: trunk, leafStatus: [funcID: .yellow])
        #expect(atlas.status(for: funcID) == .yellow)
    }

    @Test func unknownNodeIDIsUnknownNotGreen() {
        let (trunk, _, _, _) = makeTrunk()
        let atlas = TrunkAtlas(trunk: trunk, leafStatus: [:])
        #expect(atlas.status(for: "no-such-node") == .unknown)
        #expect(atlas.status(for: "no-such-node") != .green)
    }

    @Test func colourMappingIsDistinctPerStatus() {
        let green = TrunkAtlas.colour(for: .green)
        let yellow = TrunkAtlas.colour(for: .yellow)
        let red = TrunkAtlas.colour(for: .red)

        #expect(green.hue != yellow.hue)
        #expect(yellow.hue != red.hue)
        #expect(green.hue != red.hue)
    }

    @Test func emptyTrunkIsUnknownOverall() {
        let atlas = TrunkAtlas(trunk: CodeTrunk(), leafStatus: [:])
        #expect(atlas.overall == .unknown)
    }
}
