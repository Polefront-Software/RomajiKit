import Foundation

/// The part of speech the renderer and the word joiner care about.
/// The raw values are the ones the reference fixtures use.
public enum PartOfSpeech: String, Sendable, Codable, Hashable {
    case noun, verb, adj, adv, particle, aux, symbol, interj, pron
    case prefix, conj, adnominal, number, foreign, other

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PartOfSpeech(rawValue: raw) ?? .other
    }
}

/// One word of a lyric line as an analyzer sees it.
public struct LyricToken: Sendable, Hashable, Codable {
    /// The word as written in the line.
    public var surface: String
    /// The analyzer's reading, in katakana. Latin text and symbols are
    /// their own reading.
    public var reading: String
    public var pos: PartOfSpeech
    /// Written onto the word before it, with no space (待っ + て).
    public var attach: Bool
    /// Where the word sits in the displayed line, counted in characters.
    public var range: Range<Int>
    /// The analyzer is not sure of this reading: a word the dictionary
    /// does not know, a number it cannot read, a word often sung another
    /// way.
    public var needsReview: Bool
    /// Other readings worth offering, in katakana.
    public var candidates: [String]

    public init(
        surface: String,
        reading: String,
        pos: PartOfSpeech,
        attach: Bool = false,
        range: Range<Int> = 0..<0,
        needsReview: Bool = false,
        candidates: [String] = []
    ) {
        self.surface = surface
        self.reading = reading
        self.pos = pos
        self.attach = attach
        self.range = range
        self.needsReview = needsReview
        self.candidates = candidates
    }

    private enum CodingKeys: String, CodingKey {
        case surface, reading, pos, attach, range, needsReview, candidates
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        surface = try c.decode(String.self, forKey: .surface)
        reading = try c.decode(String.self, forKey: .reading)
        pos = try c.decode(PartOfSpeech.self, forKey: .pos)
        attach = try c.decodeIfPresent(Bool.self, forKey: .attach) ?? false
        range = try c.decodeIfPresent(Range<Int>.self, forKey: .range) ?? 0..<0
        needsReview = try c.decodeIfPresent(Bool.self, forKey: .needsReview) ?? false
        candidates = try c.decodeIfPresent([String].self, forKey: .candidates) ?? []
    }
}

/// Where a reading came from. A later case beats an earlier one; the
/// user's own fix beats everything.
public enum ReadingSource: String, Sendable, Codable, Hashable, CaseIterable, Comparable {
    /// The analyzer's default reading.
    case dictionary
    /// The app-wide list of known dictionary errors.
    case exception
    /// A pick among several readings (phase 2).
    case classifier
    /// What the singing sounded like (phase 3).
    case audio
    /// Furigana written in the lyrics.
    case ruby
    /// The user's own fix for this song.
    case user

    public var priority: Int {
        switch self {
        case .dictionary: 1
        case .exception: 2
        case .classifier: 3
        case .audio: 4
        case .ruby: 5
        case .user: 6
        }
    }

    public static func < (a: ReadingSource, b: ReadingSource) -> Bool {
        a.priority < b.priority
    }
}

/// A reading put forward for one token by something other than the
/// analyzer.
public struct ReadingProposal: Sendable, Hashable, Codable {
    public var reading: String
    public var source: ReadingSource
    /// The proposal is itself in doubt (an override whose lyrics changed).
    public var needsReview: Bool

    public init(reading: String, source: ReadingSource, needsReview: Bool = false) {
        self.reading = reading
        self.source = source
        self.needsReview = needsReview
    }
}

/// A token with the reading that won.
public struct ResolvedToken: Sendable, Hashable {
    public var token: LyricToken
    /// The winning reading, in kana.
    public var reading: String
    public var source: ReadingSource
    public var needsReview: Bool
    /// Every reading on offer for this word, the winner first.
    public var candidates: [String]

    public init(
        token: LyricToken, reading: String, source: ReadingSource,
        needsReview: Bool, candidates: [String]
    ) {
        self.token = token
        self.reading = reading
        self.source = source
        self.needsReview = needsReview
        self.candidates = candidates
    }
}

/// How the romaji is spelled.
public enum RomajiPreset: String, Sendable, Codable, CaseIterable, Hashable {
    /// Long vowels as written (ou, oo, aa). The default.
    case singalong
    /// Hepburn with macrons (ō).
    case learner
    /// The 2025 official notice: as written, っち as cch.
    case official
    /// Kunrei-shiki with circumflexes (ô).
    case kunrei
}

/// One token of a romanized line.
public struct RomanizedToken: Sendable, Hashable {
    public var resolved: ResolvedToken
    public var romaji: String
    /// Where this token's romaji sits in the line's `text`, in characters.
    public var romajiRange: Range<Int>

    public var surface: String { resolved.token.surface }
    public var range: Range<Int> { resolved.token.range }
    public var needsReview: Bool { resolved.needsReview }
}

/// A lyric line with its readings and its romaji.
public struct RomanizedLine: Sendable, Hashable {
    /// The line as it should be shown: ruby markup taken out.
    public var displayText: String
    public var tokens: [RomanizedToken]
    /// The romaji line.
    public var text: String
    /// The line has kana or kanji, so romaji says something the line
    /// itself does not.
    public var hasJapanese: Bool
    /// For each character of `displayText`, where it stood in the line
    /// as written; nil when the two are the same.
    public var sourceIndices: [Int]? = nil

    /// Where the singing is on the romaji for each place it can be on
    /// the line as written: one value per character boundary, so word
    /// timings made for the original carry over. A word's romaji fills
    /// evenly while the word is sung.
    public func marks(sourceCount: Int? = nil) -> [Double] {
        let count = displayText.count
        var points: [(at: Int, sung: Double)] = [(0, 0)]
        for token in tokens {
            for point in [(token.range.lowerBound, token.romajiRange.lowerBound), (token.range.upperBound, token.romajiRange.upperBound)] {
                let at = min(max(point.0, points[points.count - 1].at), count)
                points.append((at, max(Double(point.1), points[points.count - 1].sung)))
            }
        }
        points.append((count, Double(text.count)))
        var marks = [Double](repeating: 0, count: count + 1)
        for index in 1..<points.count {
            let from = points[index - 1], to = points[index]
            // At a boundary between two words the first is sung out and
            // the second not begun: the place keeps the first one's end.
            guard to.at > from.at else { continue }
            for place in (from.at + 1)...to.at {
                marks[place] = from.sung + (to.sung - from.sung) * Double(place - from.at) / Double(to.at - from.at)
            }
        }
        guard let sourceIndices, let total = sourceCount ?? sourceIndices.last.map({ $0 + 1 }) else { return marks }
        // The line as written still has its furigana markup: a place
        // inside the markup is where the word before it ended.
        var out = [Double](repeating: 0, count: total + 1)
        var shown = 0
        for place in 0...total {
            while shown < sourceIndices.count, sourceIndices[shown] < place { shown += 1 }
            out[place] = marks[min(shown, count)]
        }
        return out
    }

    /// The stretches of `text` that are marked for review.
    public var reviewRanges: [Range<Int>] {
        tokens.filter { $0.needsReview && !$0.romajiRange.isEmpty }.map(\.romajiRange)
    }

    /// The whole line's reading in hiragana, Latin left as it is.
    public var kana: String {
        tokens.map { Kana.hiragana($0.resolved.reading) }.joined()
    }
}
