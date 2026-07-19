import Testing
import Foundation
@testable import CreatureSpine

@Suite struct InterleavedDocumentTests {

    @Test func createInterleavedDocument() {
        let doc = InterleavedDocument(
            channels: [
                InterleavedChannel(index: 0, label: "rosetta", data: Data("grammar-rule".utf8)),
                InterleavedChannel(index: 1, label: "swift", data: Data("let x = 1".utf8))
            ],
            constellationKey: ConstellationKey.capture(visibleStars: [], at: Date(timeIntervalSince1970: 0)),
            daemonSignatureHash: Data(repeating: 0xAB, count: 32)
        )
        #expect(doc.channelCount == 2)
        #expect(doc.channel(at: 0)?.label == "rosetta")
        #expect(doc.channel(at: 1)?.label == "swift")
        #expect(doc.channel(at: 2) == nil)
    }

    @Test func coordinateHashProvesSemantic() {
        let data0 = Data("photosynthesis".utf8)
        let data1 = Data("光合作用".utf8)
        let doc = InterleavedDocument(
            channels: [
                InterleavedChannel(index: 0, label: "rosetta", data: data0),
                InterleavedChannel(index: 1, label: "chinese", data: data1)
            ],
            constellationKey: ConstellationKey.capture(visibleStars: [], at: Date(timeIntervalSince1970: 0)),
            daemonSignatureHash: Data(repeating: 0, count: 32)
        )
        #expect(!doc.coordinateHash.isEmpty)
        #expect(doc.coordinateHash.count == 32) // SHA-256
    }

    @Test func sameChannelsProduceSameHash() {
        let channels = [
            InterleavedChannel(index: 0, label: "a", data: Data("hello".utf8)),
            InterleavedChannel(index: 1, label: "b", data: Data("world".utf8))
        ]
        let key = ConstellationKey.capture(visibleStars: [], at: Date(timeIntervalSince1970: 0))
        let doc1 = InterleavedDocument(channels: channels, constellationKey: key, daemonSignatureHash: Data(repeating: 0, count: 32))
        let doc2 = InterleavedDocument(channels: channels, constellationKey: key, daemonSignatureHash: Data(repeating: 0, count: 32))
        #expect(doc1.coordinateHash == doc2.coordinateHash)
    }

    @Test func differentChannelsProduceDifferentHash() {
        let key = ConstellationKey.capture(visibleStars: [], at: Date(timeIntervalSince1970: 0))
        let sig = Data(repeating: 0, count: 32)
        let doc1 = InterleavedDocument(
            channels: [InterleavedChannel(index: 0, label: "a", data: Data("hello".utf8))],
            constellationKey: key, daemonSignatureHash: sig
        )
        let doc2 = InterleavedDocument(
            channels: [InterleavedChannel(index: 0, label: "a", data: Data("world".utf8))],
            constellationKey: key, daemonSignatureHash: sig
        )
        #expect(doc1.coordinateHash != doc2.coordinateHash)
    }

    @Test func bondHashCombinesAllThreeKeys() {
        var memorySystem = MemoryOrbitSystem()
        memorySystem.add(MemoryOrbit(
            label: "test", semiMajorAxis: 0.5, eccentricity: 0.2, orbitalPeriod: 7,
            dimensions: MemoryDimensions(emotional: 1.0)
        ))
        let constellationKey = ConstellationKey.capture(
            visibleStars: [GAIAStar(sourceID: "1", ra: 0, dec: 0, parallax: 0, properMotionRA: 0, properMotionDEC: 0)],
            at: Date(timeIntervalSince1970: 1000)
        )
        let daemonSigHash = Data(repeating: 0xCD, count: 32)

        let doc = InterleavedDocument(
            channels: [InterleavedChannel(index: 0, label: "rosetta", data: Data("test".utf8))],
            constellationKey: constellationKey,
            daemonSignatureHash: daemonSigHash
        )
        let bondHash = doc.bondHash(humanKey: memorySystem.deriveKey(at: Date(timeIntervalSince1970: 1000)))
        #expect(bondHash.count == 32)
    }

    @Test func interleavedDocumentCodable() throws {
        let doc = InterleavedDocument(
            channels: [InterleavedChannel(index: 0, label: "rosetta", data: Data("test".utf8))],
            constellationKey: ConstellationKey.capture(visibleStars: [], at: Date(timeIntervalSince1970: 0)),
            daemonSignatureHash: Data(repeating: 0, count: 32)
        )
        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(InterleavedDocument.self, from: data)
        #expect(decoded.channelCount == doc.channelCount)
        #expect(decoded.coordinateHash == doc.coordinateHash)
    }
}
