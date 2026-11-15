import Foundation

/// Lyric lines to romaji: analyze, read numbers, apply the exception
/// list, lay furigana and the song's own fixes on top, resolve, render.
public struct RomajiEngine: Sendable {
    public let analyzer: any JapaneseAnalyzer
    public let numbers: NumberReader?
    public let exceptions: ExceptionList
    public let gikun: GikunHints
    public let store: OverrideStore?
    /// Picks among a word's readings from its surroundings; none unless
    /// one is given.
    public let disambiguator: (any ReadingDisambiguator)?

    public init(
        analyzer: any JapaneseAnalyzer,
        numbers: NumberReader? = NumberReader(),
        exceptions: ExceptionList = .bundled,
        gikun: GikunHints = .bundled,
        store: OverrideStore? = nil,
        disambiguator: (any ReadingDisambiguator)? = nil
    ) {
        self.analyzer = analyzer
        self.numbers = numbers
        self.exceptions = exceptions
        self.gikun = gikun
        self.store = store
        self.disambiguator = disambiguator
    }

    /// The base tier: MeCab with the pack's dictionary and lists.
    /// Throws if the dictionary cannot be opened.
    public init(
        pack: DictionaryPack, store: OverrideStore? = nil, disambiguator: (any ReadingDisambiguator)? = nil
    ) throws {
        self.init(
            analyzer: try MecabAnalyzer(dictionary: pack.folder), exceptions: pack.exceptions, gikun: pack.gikun,
            store: store, disambiguator: disambiguator)
    }

    /// Shown in the scorer's report.
    public var name: String {
        analyzer.name + (numbers == nil ? "" : "+numbers") + (exceptions.entries.isEmpty ? "" : "+exceptions")
    }

    /// One line, with the song's stored fixes. The line's own text
    /// stands in for the lyrics when only a line is at hand.
    public func romanize(line: String, songID: SongIdentity, preset: RomajiPreset = .singalong) async -> RomanizedLine {
        let overrides = await store?.overrides(for: songID, lyricsHash: LyricsHash.make([line])) ?? .none()
        return romanize(line: line, lineIndex: 0, overrides: overrides, preset: preset)
    }

    /// A whole song, with its stored fixes.
    public func romanize(
        lyrics lines: [String], songID: SongIdentity, preset: RomajiPreset = .singalong
    ) async -> [RomanizedLine] {
        let overrides = await store?.overrides(for: songID, lyricsHash: LyricsHash.make(lines)) ?? .none()
        return romanize(lyrics: lines, overrides: overrides, preset: preset)
    }

    public func romanize(
        lyrics lines: [String], overrides: SongOverrides = .none(), preset: RomajiPreset = .singalong
    ) -> [RomanizedLine] {
        lines.enumerated().map { romanize(line: $1, lineIndex: $0, overrides: overrides, preset: preset) }
    }

    /// One line. `ruby` adds furigana known from elsewhere to what is
    /// written in the line itself; its ranges count the displayed text.
    public func romanize(
        line: String,
        lineIndex: Int = 0,
        overrides: SongOverrides = .none(),
        ruby: [RubyAnnotation] = [],
        preset: RomajiPreset = .singalong
    ) -> RomanizedLine {
        let parsed = RubyParser.parse(line)
        let text = parsed.text
        guard Kana.hasJapanese(text) else {
            return RomanizedLine(
                displayText: text, tokens: [], text: text, hasJapanese: false, sourceIndices: parsed.sourceIndices)
        }
        var tokens = exceptions.analyze(text, with: analyzer)
        if let numbers { tokens = numbers.apply(tokens) }
        let excepted = exceptions.apply(tokens).map { (token: gikun.apply($0.token), proposal: $0.proposal) }
        var items = RubyApplier.apply(parsed.annotations + ruby, to: excepted)

        // What the surroundings say about words with more than one
        // reading. A stretch whose reading is written in the lyrics is
        // left as it is.
        let characters = Array(text)
        for pick in disambiguator?.picks(for: items.map(\.token), in: text) ?? [] {
            guard pick.range.lowerBound >= 0, pick.range.upperBound <= characters.count, !pick.range.isEmpty,
                !items.contains(where: { item in
                    item.token.range.overlaps(pick.range)
                        && item.proposals.contains { $0.source > ReadingSource.classifier }
                })
            else { continue }
            items = Self.cover(pick.range, in: items)
            guard let index = items.firstIndex(where: { $0.token.range == pick.range }) else { continue }
            for candidate in pick.candidates where !items[index].token.candidates.contains(candidate) {
                items[index].token.candidates.append(candidate)
            }
            items[index].proposals.append(
                ReadingProposal(reading: pick.reading, source: .classifier, needsReview: pick.needsReview))
        }

        // The song's own fixes, where the word is still what it was.
        for o in overrides.forLine(lineIndex) {
            guard o.range.lowerBound >= 0, o.range.upperBound <= characters.count,
                String(characters[o.range]) == o.surface
            else { continue }
            items = Self.cover(o.range, in: items)
            if let index = items.firstIndex(where: { $0.token.range == o.range }) {
                items[index].proposals.append(
                    ReadingProposal(reading: o.reading, source: o.source, needsReview: overrides.isStale(o)))
            }
        }

        let resolved = items.map { ReadingResolver.resolve(token: $0.token, proposals: $0.proposals) }
        let finalTokens = resolved.map(\.token)
        let rendered = RomajiRenderer.renderLine(tokens: finalTokens, readings: resolved.map(\.reading), preset: preset)

        var out: [RomanizedToken] = []
        var cursor = 0
        var wordStarted = false
        for (r, romaji) in zip(resolved, rendered.tokens) {
            if !(r.token.attach && wordStarted) {
                if wordStarted { cursor += 1 }  // the space between words
                wordStarted = true
            }
            let length = romaji.count
            out.append(RomanizedToken(resolved: r, romaji: romaji, romajiRange: cursor..<(cursor + length)))
            cursor += length
        }
        return RomanizedLine(
            displayText: text, tokens: out, text: rendered.text, hasJapanese: true,
            sourceIndices: parsed.sourceIndices)
    }

    /// Makes one token of exactly `range`, joining or cutting the tokens
    /// it touches, so a fix set on a stretch of the line has a token to
    /// sit on. Left as it is when the range cuts a token in a way that
    /// cannot be split cleanly.
    private static func cover(
        _ range: Range<Int>, in items: [(token: LyricToken, proposals: [ReadingProposal])]
    ) -> [(token: LyricToken, proposals: [ReadingProposal])] {
        if items.contains(where: { $0.token.range == range }) { return items }
        let touched = items.indices.filter { items[$0].token.range.overlaps(range) }
        guard let first = touched.first, let last = touched.last,
            items[first].token.range.lowerBound == range.lowerBound,
            items[last].token.range.upperBound == range.upperBound
        else { return items }
        var merged = items[first].token
        merged.surface = touched.map { items[$0].token.surface }.joined()
        merged.reading = touched.map { items[$0].token.reading }.joined()
        merged.range = range
        merged.candidates = []
        var out = items
        out.replaceSubrange(first...last, with: [(merged, [])])
        return out
    }
}
