import Foundation
import Testing
@testable import RomajiKit

/// The renderer against the hand-checked fixture, every line in every
/// preset, exactly. The fixture is the spec.
@Suite struct RendererFixtureTests {
    @Test func everyFixtureLineInEveryPreset() throws {
        let fixture = try JSONDecoder().decode(RendererFixture.self, from: TestSupport.fixture("renderer_cases.json"))
        #expect(fixture.cases.count >= 16)
        var total = 0
        var failures: [String] = []
        for c in fixture.cases {
            let resolved = c.tokens.enumerated().map { index, token in
                ReadingResolver.resolve(
                    token: token,
                    proposals: (c.overrides ?? []).filter { $0.token == index }
                        .map { ReadingProposal(reading: $0.reading, source: $0.source) })
            }
            for name in fixture.presets {
                let preset = try #require(RomajiPreset(rawValue: name))
                let expected = try #require(c.expected[name])
                let got = RomajiRenderer.renderLine(tokens: c.tokens, readings: resolved.map(\.reading), preset: preset).text
                total += 1
                if got != expected { failures.append("\(c.id) [\(name)] got \(got), expected \(expected) (\(c.note))") }
            }
        }
        print("Renderer fixtures: \(total - failures.count)/\(total) passed")
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
        #expect(total == fixture.cases.count * 4)
    }

    @Test func prioritiesAreTheReferences() {
        #expect(ReadingSource.allCases.map(\.priority) == [1, 2, 3, 4, 5, 6])
        let token = LyricToken(surface: "本気", reading: "ホンキ", pos: .noun)
        let r = ReadingResolver.resolve(
            token: token,
            proposals: [
                ReadingProposal(reading: "ホンキ", source: .classifier),
                ReadingProposal(reading: "マジ", source: .user),
                ReadingProposal(reading: "ホンキ", source: .ruby),
            ])
        #expect(r.reading == "マジ")
        #expect(r.source == .user)
    }

    /// The five bugs the kit's README names, each on its own.
    @Test func bugsFoundInTheReferenceStayOut() {
        func line(_ tokens: [LyricToken], _ preset: RomajiPreset = .singalong) -> String {
            RomajiRenderer.renderLine(tokens: tokens, readings: tokens.map(\.reading), preset: preset).text
        }
        // 1. ん takes no apostrophe from the next separate word.
        #expect(line([.init(surface: "瞬間", reading: "シュンカン", pos: .noun), .init(surface: "へ", reading: "ヘ", pos: .particle)]) == "shunkan e")
        // 2. っ at the end of a token doubles into an attached ending.
        #expect(line([.init(surface: "降っ", reading: "フッ", pos: .verb), .init(surface: "て", reading: "テ", pos: .particle, attach: true)]) == "futte")
        // 3. No next sound is not a vowel.
        #expect(RomajiRenderer.renderToken(reading: "ホン", pos: .noun, preset: .singalong) == "hon")
        #expect(RomajiRenderer.renderToken(reading: "アッ", pos: .interj, preset: .singalong) == "a")
        // 4. っ before punctuation doubles nothing.
        #expect(line([.init(surface: "あっ", reading: "アッ", pos: .interj), .init(surface: "、", reading: "、", pos: .symbol, attach: true)]) == "a,")
        // 5. Small kana and ヷ to ヺ are in the table.
        for (kana, romaji) in [("ゎ", "wa"), ("ヵ", "ka"), ("ヶ", "ke"), ("ヷ", "va"), ("ヸ", "vi"), ("ヹ", "ve"), ("ヺ", "vo")] {
            #expect(RomajiRenderer.renderToken(reading: kana, pos: .noun, preset: .singalong) == romaji)
        }
    }
}
