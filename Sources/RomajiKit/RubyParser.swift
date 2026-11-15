import Foundation

/// Furigana for a stretch of a line.
public struct RubyAnnotation: Sendable, Hashable, Codable {
    /// The annotated characters, in the displayed line.
    public var range: Range<Int>
    /// The reading, in kana.
    public var reading: String

    public init(range: Range<Int>, reading: String) {
        self.range = range
        self.reading = reading
    }
}

/// Reads furigana written into a lyric line and takes the markup out.
///
/// Four spellings: 運命(さだめ), 運命（さだめ）, |運命《さだめ》 (the bar is
/// optional when the base is all kanji) and {運命|さだめ}. Brackets that
/// hold anything but kana are left alone: (Yeah) is not a reading.
public enum RubyParser {
    public struct Parsed: Sendable, Hashable {
        /// The line with the markup removed.
        public var text: String
        public var annotations: [RubyAnnotation]
        /// For each character of `text`, where it stood in the line as
        /// written; nil when nothing was taken out.
        public var sourceIndices: [Int]?
    }

    public static func parse(_ line: String) -> Parsed {
        let chars = Array(line)
        var out: [Character] = []
        var from: [Int] = []
        var annotations: [RubyAnnotation] = []
        /// Where an explicit base started (after | or ｜), in `out`.
        var barStart: Int?
        var i = 0

        func kana(from start: Int, closing: Character) -> (reading: String, end: Int)? {
            var j = start
            var reading = ""
            while j < chars.count, chars[j] != closing {
                guard chars[j].unicodeScalars.allSatisfy(Kana.isReadingKana) else { return nil }
                reading.append(chars[j])
                j += 1
            }
            guard j < chars.count, !reading.isEmpty else { return nil }
            return (reading, j + 1)
        }

        /// The kanji just before the bracket: what an unmarked reading belongs to.
        func kanjiRunStart() -> Int? {
            var k = out.count
            while k > 0, out[k - 1].unicodeScalars.allSatisfy(Kana.isKanji) { k -= 1 }
            return k < out.count ? k : nil
        }

        while i < chars.count {
            let ch = chars[i]
            switch ch {
            case "|", "｜":
                // A bar only means something when 《 follows later.
                if let close = chars[i...].firstIndex(of: "《"), close > i + 1,
                    !chars[(i + 1)..<close].contains(where: { $0 == "|" || $0 == "｜" || $0 == "》" })
                {
                    barStart = out.count
                    i += 1
                    continue
                }
            case "《":
                if let (reading, end) = kana(from: i + 1, closing: "》"),
                    let start = barStart ?? kanjiRunStart(), start < out.count
                {
                    annotations.append(RubyAnnotation(range: start..<out.count, reading: reading))
                    barStart = nil
                    i = end
                    continue
                }
            case "(", "（":
                if let (reading, end) = kana(from: i + 1, closing: ch == "(" ? ")" : "）"), let start = kanjiRunStart() {
                    annotations.append(RubyAnnotation(range: start..<out.count, reading: reading))
                    i = end
                    continue
                }
            case "{":
                if let close = chars[i...].firstIndex(of: "}"),
                    let bar = chars[i..<close].firstIndex(where: { $0 == "|" || $0 == "｜" }), bar > i + 1
                {
                    let reading = String(chars[(bar + 1)..<close])
                    if !reading.isEmpty, reading.unicodeScalars.allSatisfy(Kana.isReadingKana) {
                        let start = out.count
                        out.append(contentsOf: chars[(i + 1)..<bar])
                        from.append(contentsOf: (i + 1)..<bar)
                        annotations.append(RubyAnnotation(range: start..<out.count, reading: reading))
                        i = close + 1
                        continue
                    }
                }
            default:
                break
            }
            out.append(ch)
            from.append(i)
            i += 1
        }
        return Parsed(
            text: String(out), annotations: annotations, sourceIndices: out.count == chars.count ? nil : from)
    }
}

/// Lays furigana over the analyzer's tokens.
enum RubyApplier {
    /// Tokens with a `.ruby` proposal where furigana covers them. Tokens
    /// the furigana cuts across are joined into one first.
    static func apply(
        _ annotations: [RubyAnnotation], to items: [(token: LyricToken, proposal: ReadingProposal?)]
    ) -> [(token: LyricToken, proposals: [ReadingProposal])] {
        var out: [(token: LyricToken, proposals: [ReadingProposal])] = []
        let sorted = annotations.filter { !$0.range.isEmpty }.sorted { $0.range.lowerBound < $1.range.lowerBound }
        var i = 0
        while i < items.count {
            let token = items[i].token
            var touching = sorted.filter { $0.range.overlaps(token.range) }
            guard !touching.isEmpty else {
                out.append((token, items[i].proposal.map { [$0] } ?? []))
                i += 1
                continue
            }
            // Everything the furigana reaches, however the analyzer cut it.
            var end = i + 1
            var span = token.range
            var grew = true
            while grew {
                grew = false
                let reach = touching.map(\.range.upperBound).max() ?? span.upperBound
                while end < items.count, items[end].token.range.lowerBound < reach {
                    span = span.lowerBound..<items[end].token.range.upperBound
                    end += 1
                    grew = true
                }
                let more = sorted.filter { $0.range.overlaps(span) }
                if more.count != touching.count {
                    touching = more
                    grew = true
                }
            }
            let group = items[i..<end]
            var merged = token
            merged.surface = group.map(\.token.surface).joined()
            merged.range = span
            // The reading without furigana: exceptions included, since
            // furigana on one kanji leaves the others to the dictionary.
            let plain = group.map { $0.proposal?.reading ?? $0.token.reading }.joined()
            merged.reading = group.map(\.token.reading).joined()
            merged.needsReview = group.contains { $0.token.needsReview }
            merged.candidates = group.count == 1 ? token.candidates : []

            var proposals: [ReadingProposal] = []
            if group.count == 1, let p = items[i].proposal { proposals.append(p) }
            if let reading = reading(surface: Array(merged.surface), span: span, annotations: touching, plain: plain) {
                proposals.append(ReadingProposal(reading: reading, source: .ruby))
            } else {
                // Furigana on part of a word, and the rest cannot be
                // told apart: keep the dictionary and ask.
                merged.needsReview = true
            }
            out.append((merged, proposals))
            i = end
        }
        return out
    }

    /// The reading of a word some of whose characters carry furigana:
    /// furigana where there is some, kana as itself, and for kanji
    /// without furigana whatever the dictionary reading has left there.
    private static func reading(
        surface: [Character], span: Range<Int>, annotations: [RubyAnnotation], plain: String
    ) -> String? {
        enum Piece {
            case fixed(String)
            case open
        }
        var pieces: [Piece] = []
        var k = span.lowerBound
        var hasOpen = false
        func add(fixed s: String) {
            if case .fixed(let last)? = pieces.last {
                pieces[pieces.count - 1] = .fixed(last + s)
            } else {
                pieces.append(.fixed(s))
            }
        }
        var rubyPieces = Set<Int>()
        while k < span.upperBound {
            if let a = annotations.first(where: { $0.range.lowerBound <= k && k < $0.range.upperBound }) {
                pieces.append(.fixed(Kana.katakana(a.reading)))
                rubyPieces.insert(pieces.count - 1)
                k = max(k + 1, min(a.range.upperBound, span.upperBound))
                continue
            }
            let ch = surface[k - span.lowerBound]
            if ch.unicodeScalars.allSatisfy(Kana.isReadingKana) {
                // Kana right after furigana must not be glued to it.
                if rubyPieces.contains(pieces.count - 1) { pieces.append(.fixed("")) }
                add(fixed: Kana.katakana(String(ch)))
            } else {
                if case .open? = pieces.last {} else { pieces.append(.open) }
                hasOpen = true
            }
            k += 1
        }
        if !hasOpen {
            return pieces.map { if case .fixed(let s) = $0 { s } else { "" } }.joined()
        }
        // Kanji without furigana: find what the dictionary reading has
        // between the kana that is written out. The furigana pieces are
        // open too in the dictionary's reading, so match the written
        // kana only.
        var pattern = "^"
        var groupForOpen: [Int: Int] = [:]
        var groups = 0
        for (index, piece) in pieces.enumerated() {
            switch piece {
            case .fixed(let s):
                if rubyPieces.contains(index) {
                    pattern += "(?:.+?)"
                } else {
                    pattern += NSRegularExpression.escapedPattern(for: s)
                }
            case .open:
                groups += 1
                groupForOpen[index] = groups
                pattern += "(.+?)"
            }
        }
        pattern += "$"
        let plainKana = Kana.katakana(plain)
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: plainKana, range: NSRange(plainKana.startIndex..., in: plainKana))
        else { return nil }
        var out = ""
        for (index, piece) in pieces.enumerated() {
            switch piece {
            case .fixed(let s): out += s
            case .open:
                guard let g = groupForOpen[index], let r = Range(match.range(at: g), in: plainKana) else { return nil }
                out += plainKana[r]
            }
        }
        return out
    }
}
