import Foundation
import Testing
@testable import RomajiKit

/// The same check as `tools/fuzz_reference.py`: random kana in every
/// preset must never leave a Japanese character in the output.
@Suite struct RendererFuzzTests {
    @Test func randomKanaLeavesNoKana() {
        var rng = SplitMix64(state: 42)
        let kana: [Unicode.Scalar] =
            (0x3041..<0x3097).compactMap(Unicode.Scalar.init) + (0x30A1..<0x30FB).compactMap(Unicode.Scalar.init) + ["ー"]
        let iterations = 20_000
        var leaks: [String] = []
        var renders = 0
        for preset in RomajiPreset.allCases {
            for _ in 0..<iterations {
                var view = String.UnicodeScalarView()
                for _ in 0..<Int.random(in: 1...6, using: &rng) { view.append(kana.randomElement(using: &rng)!) }
                let s = String(view)
                for pos in [PartOfSpeech.noun, .verb, .particle] {
                    let out = RomajiRenderer.renderToken(reading: s, pos: pos, preset: preset)
                    renders += 1
                    if out.unicodeScalars.contains(where: { $0.value >= 0x3040 && $0.value <= 0x30FF }) {
                        leaks.append("\(preset) \(pos) \(s) -> \(out)")
                    }
                }
            }
        }
        print("Renderer fuzz: \(leaks.count) leaks in \(renders) renders")
        #expect(leaks.isEmpty, "\(leaks.prefix(10).joined(separator: "\n"))")
    }

    /// Random lines through the whole pipeline: no kana or kanji left,
    /// and every token's range lies inside the line.
    @Test func wholeLinesLeaveNoKana() {
        var rng = SplitMix64(state: 7)
        let pieces = [
            "夜空", "に", "星", "が", "光る", "君", "の", "声", "を", "聞い", "て", "いる", "100", "回", "目", "Love", "、",
            "。", "待っ", "て", "東京", "へ", "行こ", "う", "！", "「", "」", "ん", "っ", "ー", "一人", "三", "本", " ", "　",
            "ずっと", "抱きしめ", "たい", "泣か", "ない", "で", "（", "）", "Don't", "24", "時間", "パーティー", "は",
        ]
        let engine = TestSupport.engine
        for _ in 0..<2_000 {
            let line = (0..<Int.random(in: 1...8, using: &rng)).map { _ in pieces.randomElement(using: &rng)! }.joined()
            for preset in RomajiPreset.allCases {
                let r = engine.romanize(line: line, preset: preset)
                #expect(!Kana.hasJapanese(r.text), "\(line) -> \(r.text)")
                let count = r.displayText.count
                var end = 0
                for t in r.tokens {
                    #expect(t.range.lowerBound >= end && t.range.upperBound <= count, "\(line): \(t.surface) \(t.range)")
                    end = t.range.upperBound
                    #expect(String(Array(r.displayText.precomposedStringWithCanonicalMapping)[t.range]) == t.surface)
                    #expect(String(Array(r.text)[t.romajiRange]) == t.romaji, "\(line) -> \(r.text): \(t.romaji) \(t.romajiRange)")
                }
            }
        }
    }
}
