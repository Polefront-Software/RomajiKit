import Foundation
import IPADic
@testable import RomajiKit

/// The test kit beside the package: fixtures, the reference, the scorer.
enum TestSupport {
    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("TestSupport")

    static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent("fixtures").appendingPathComponent(name))
    }

    /// What the suites read with: the full IPAdic, or the pack the
    /// environment names (ROMAJI_PACK, as scripts/romaji-eval.sh sets it
    /// to check the pack the app fetches).
    static let pack: DictionaryPack = {
        if let folder = ProcessInfo.processInfo.environment["ROMAJI_PACK"], !folder.isEmpty {
            return DictionaryPack(folder: URL(fileURLWithPath: folder, isDirectory: true), version: "given")
        }
        return DictionaryPack(folder: IPADic().url, version: "ipadic")
    }()

    /// One analyzer for all suites: opening the dictionary once is enough.
    static let engine: RomajiEngine = {
        guard let engine = try? RomajiEngine(pack: pack) else { fatalError("The dictionary could not be opened") }
        return engine
    }()
}

struct RendererFixture: Decodable {
    struct Override: Decodable {
        var token: Int
        var reading: String
        var source: ReadingSource
    }
    struct Case: Decodable {
        var id: String
        var note: String
        var tokens: [LyricToken]
        var expected: [String: String]
        var overrides: [Override]?
    }
    var presets: [String]
    var cases: [Case]
}

struct ReadingFixture: Decodable {
    struct Word: Decodable {
        var surface: String
        var reading: String
    }
    struct Case: Decodable {
        var id: String
        var category: String
        var text: String
        var expected: String
        var ruby: [Word]?
        var focus: [Word]?
    }
    var cases: [Case]
}

/// A small seeded generator, so the fuzz is the same on every run.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
