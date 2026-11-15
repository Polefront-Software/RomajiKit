import Foundation
import Testing
@testable import RomajiKit

/// The whole pipeline over the reading fixture. Writes the results in
/// the scorer's format; `scripts/romaji-eval.sh` hands them to
/// `tools/score_readings.py`.
@Suite struct ReadingAccuracyTests {
    struct Span: Encodable {
        var surface: String
        var reading: String
        var source: String
        var needs_review: Bool
    }
    struct CaseResult: Encodable {
        var id: String
        var reading: String
        var romaji: String
        var spans: [Span]
    }
    struct Results: Encodable {
        var engine: String
        var cases: [CaseResult]
    }

    /// One span per written word: a verb with its endings is one span,
    /// as the scorer's focus words are written.
    static func spans(_ line: RomanizedLine) -> [Span] {
        var out: [Span] = []
        var sources: [ReadingSource] = []
        for t in line.tokens {
            let reading = Kana.hiragana(t.resolved.reading)
            if t.resolved.token.attach, !out.isEmpty, t.resolved.token.pos != .symbol {
                out[out.count - 1].surface += t.surface
                out[out.count - 1].reading += reading
                out[out.count - 1].needs_review = out[out.count - 1].needs_review || t.needsReview
                sources[sources.count - 1] = max(sources[sources.count - 1], t.resolved.source)
                out[out.count - 1].source = sources[sources.count - 1].rawValue
            } else {
                out.append(Span(surface: t.surface, reading: reading, source: t.resolved.source.rawValue, needs_review: t.needsReview))
                sources.append(t.resolved.source)
            }
        }
        return out
    }

    static func run(_ fixture: ReadingFixture, engine: RomajiEngine) -> Results {
        var cases: [CaseResult] = []
        for c in fixture.cases {
            // Furigana from the case's own field, laid where the word is.
            var ruby: [RubyAnnotation] = []
            let chars = Array(c.text)
            for word in c.ruby ?? [] {
                let needle = Array(word.surface)
                if let start = (0...(chars.count - needle.count)).first(where: { Array(chars[$0..<($0 + needle.count)]) == needle }) {
                    ruby.append(RubyAnnotation(range: start..<(start + needle.count), reading: word.reading))
                }
            }
            let line = engine.romanize(line: c.text, ruby: ruby)
            cases.append(CaseResult(id: c.id, reading: line.kana, romaji: line.text, spans: spans(line)))
        }
        return Results(engine: engine.name, cases: cases)
    }

    static func norm(_ s: String) -> String {
        Kana.hiragana(s).lowercased().filter { !" 、。，．,.!?！？「」『』…・〜~".contains($0) }
    }

    @Test func readingFixture() throws {
        let fixture = try JSONDecoder().decode(ReadingFixture.self, from: TestSupport.fixture("reading_cases.json"))
        let results = Self.run(fixture, engine: TestSupport.engine)

        let dir = ProcessInfo.processInfo.environment["TMPDIR"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("romaji-results.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try encoder.encode(results).write(to: url)
        print("Romaji results: \(url.path)")

        let byID = Dictionary(uniqueKeysWithValues: results.cases.map { ($0.id, $0) })
        var exact = 0, lines = 0, focusHit = 0, focusTotal = 0
        for c in fixture.cases {
            let r = try #require(byID[c.id])
            let right = Self.norm(r.reading) == Self.norm(c.expected)
            switch c.category {
            case "gikun_ruby":
                // Gate: furigana always wins.
                #expect(right, "\(c.id): \(r.reading), expected \(c.expected)")
            case "gikun_unmarked":
                // Gate: a word that may be sung another way is marked.
                for word in c.focus ?? [] {
                    let span = r.spans.first { $0.surface == word.surface } ?? r.spans.first { $0.surface.contains(word.surface) }
                    #expect(span?.needs_review == true, "\(c.id): \(word.surface) is not marked for review")
                }
            default:
                lines += 1
                if right { exact += 1 }
                for word in c.focus ?? [] {
                    focusTotal += 1
                    if let span = r.spans.first(where: { $0.surface == word.surface }) {
                        if Self.norm(span.reading) == Self.norm(word.reading) { focusHit += 1 }
                    } else if let span = r.spans.first(where: { $0.surface.contains(word.surface) }),
                        Self.norm(span.reading).contains(Self.norm(word.reading))
                    {
                        focusHit += 1
                    }
                }
            }
        }
        print("Reading fixture: \(exact)/\(lines) lines exact, \(focusHit)/\(focusTotal) focus words (alternatives not counted here; the scorer does)")
        // The floor agreed for the base tier; the scorer's own gates are
        // 85% and 90% and count accepted alternatives too.
        #expect(Double(exact) / Double(lines) >= 0.85)
        #expect(Double(focusHit) / Double(focusTotal) >= 0.90)
    }

    /// The private real-song set, when it is on this machine. Never in
    /// the repository; nothing from it is printed.
    @Test func privateSongs() throws {
        let url = TestSupport.root.appendingPathComponent("fixtures/private/songs.json")
        guard let data = try? Data(contentsOf: url) else { return }
        let fixture = try JSONDecoder().decode(ReadingFixture.self, from: data)
        var results = Self.run(fixture, engine: TestSupport.engine)
        results.cases = results.cases.map { var c = $0; c.romaji = ""; return c }
        let dir = ProcessInfo.processInfo.environment["TMPDIR"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.temporaryDirectory
        let out = dir.appendingPathComponent("romaji-results-private.json")
        try JSONEncoder().encode(results).write(to: out)
        print("Romaji private results: \(out.path)")
    }
}
