import Foundation

/// Words the dictionary reads wrongly, with the right reading. App-wide,
/// so only for readings that are wrong everywhere; what one song sings
/// differently belongs in that song's overrides.
public struct ExceptionList: Sendable {
    public struct Entry: Sendable, Codable, Hashable {
        /// The word as written. May span several of the analyzer's
        /// tokens (彷徨 + う); they are joined into one.
        public var surface: String
        /// The right reading, in katakana.
        public var reading: String
        /// The part of speech of the joined word, when the analyzer cut
        /// it wrongly.
        public var pos: PartOfSpeech?
        /// Applies only when the next word is one of these.
        public var next: [String]?
        /// Applies only when the word before is one of these.
        public var previous: [String]?
        /// A word the dictionary cuts across its edges (ひとりぼっち as
        /// ひとり, ぼっ, ちの): it is taken out of the line before the
        /// analyzer sees it, and given this reading.
        public var pin: Bool?
        public var note: String?
    }

    private struct File: Codable {
        var version: Int
        var entries: [Entry]
    }

    public let entries: [Entry]
    private let bySurface: [String: [Entry]]
    private let longest: Int

    private let pins: [(surface: [Character], entry: Entry)]

    public init(entries: [Entry]) {
        self.entries = entries
        let matched = entries.filter { $0.pin != true }
        bySurface = Dictionary(grouping: matched, by: \.surface)
        longest = matched.map(\.surface.count).max() ?? 0
        pins = entries.filter { $0.pin == true }.map { (Array($0.surface), $0) }
            .sorted { $0.surface.count > $1.surface.count }
    }

    /// Analyzes a line with the pinned words taken out first.
    func analyze(_ text: String, with analyzer: any JapaneseAnalyzer) -> [LyricToken] {
        guard !pins.isEmpty else { return analyzer.analyze(text) }
        let chars = Array(text.precomposedStringWithCanonicalMapping)
        var found: [(range: Range<Int>, entry: Entry)] = []
        var i = 0
        while i < chars.count {
            if let pin = pins.first(where: { i + $0.surface.count <= chars.count && Array(chars[i..<(i + $0.surface.count)]) == $0.surface }) {
                found.append((i..<(i + pin.surface.count), pin.entry))
                i += pin.surface.count
            } else {
                i += 1
            }
        }
        guard !found.isEmpty else { return analyzer.analyze(text) }
        var out: [LyricToken] = []
        var cursor = 0
        func piece(_ range: Range<Int>) {
            guard !range.isEmpty else { return }
            for var token in analyzer.analyze(String(chars[range])) {
                token.range = (token.range.lowerBound + range.lowerBound)..<(token.range.upperBound + range.lowerBound)
                out.append(token)
            }
        }
        for (range, entry) in found {
            piece(cursor..<range.lowerBound)
            out.append(LyricToken(surface: entry.surface, reading: entry.reading, pos: entry.pos ?? .noun, range: range))
            cursor = range.upperBound
        }
        piece(cursor..<chars.count)
        return out
    }

    public init(data: Data) throws {
        self.init(entries: try JSONDecoder().decode(File.self, from: data).entries)
    }

    public static let empty = ExceptionList(entries: [])

    /// The list shipped with the package.
    public static let bundled: ExceptionList = {
        guard let url = Bundle.module.url(forResource: "exceptions", withExtension: "json"),
            let data = try? Data(contentsOf: url), let list = try? ExceptionList(data: data)
        else { return .empty }
        return list
    }()

    /// Joins tokens where an entry spans several, and returns for each
    /// token the reading an entry proposes, if any.
    public func apply(_ tokens: [LyricToken]) -> [(token: LyricToken, proposal: ReadingProposal?)] {
        guard longest > 0 else { return tokens.map { ($0, nil) } }
        var out: [(token: LyricToken, proposal: ReadingProposal?)] = []
        var i = 0
        while i < tokens.count {
            var matched = false
            // Longest stretch of touching tokens first.
            var j = i
            var surface = ""
            var ends: [(end: Int, surface: String)] = []
            while j < tokens.count, j - i < 4, surface.count < longest {
                if j > i, tokens[j].range.lowerBound != tokens[j - 1].range.upperBound { break }
                surface += tokens[j].surface
                j += 1
                ends.append((j, surface))
            }
            for (end, surface) in ends.reversed() {
                guard let candidates = bySurface[surface] else { continue }
                let previous = out.last?.token.surface
                let next = end < tokens.count ? tokens[end].surface : nil
                guard
                    let entry = candidates.first(where: { e in
                        (e.next == nil || next.map { e.next!.contains($0) } == true)
                            && (e.previous == nil || previous.map { e.previous!.contains($0) } == true)
                    })
                else { continue }
                var token = tokens[i]
                token.surface = surface
                token.range = tokens[i].range.lowerBound..<tokens[end - 1].range.upperBound
                if end - i > 1 {
                    // The dictionary's reading of the pieces, kept as the
                    // analyzer's own answer.
                    token.reading = tokens[i..<end].map(\.reading).joined()
                    token.needsReview = false
                }
                if let pos = entry.pos { token.pos = pos }
                let same = Kana.katakana(token.reading) == Kana.katakana(entry.reading)
                out.append((token, same ? nil : ReadingProposal(reading: entry.reading, source: .exception)))
                i = end
                matched = true
                break
            }
            if !matched {
                out.append((tokens[i], nil))
                i += 1
            }
        }
        return out
    }
}

/// Words often sung with a reading the text does not show (運命 as
/// さだめ). Nothing here changes a reading: the word is only marked for
/// review, with what it might be, because no dictionary can know what
/// this song sings.
public struct GikunHints: Sendable {
    private struct File: Codable {
        var version: Int
        var words: [String: [String]]
    }

    /// Word to the readings it is sometimes sung with, in katakana.
    public let words: [String: [String]]

    public init(words: [String: [String]]) { self.words = words }

    public init(data: Data) throws {
        self.init(words: try JSONDecoder().decode(File.self, from: data).words)
    }

    public static let empty = GikunHints(words: [:])

    public static let bundled: GikunHints = {
        guard let url = Bundle.module.url(forResource: "gikun-hints", withExtension: "json"),
            let data = try? Data(contentsOf: url), let hints = try? GikunHints(data: data)
        else { return .empty }
        return hints
    }()

    public func apply(_ token: LyricToken) -> LyricToken {
        guard let readings = words[token.surface] else { return token }
        var token = token
        token.needsReview = true
        for reading in readings where !token.candidates.contains(reading) && reading != token.reading {
            token.candidates.append(reading)
        }
        return token
    }
}

/// The licences of what the package carries: MeCab, the IPA dictionary
/// and Mecab-Swift. The IPAdic terms ask that they go with every copy,
/// so the app shows this text.
public enum ThirdPartyNotices {
    public static let text: String = {
        guard let url = Bundle.module.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return text
    }()
}
