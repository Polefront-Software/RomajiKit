import Foundation
import mecab

/// MeCab with an IPAdic dictionary: the base tier.
///
/// MeCab's own C interface is used rather than Mecab-Swift's `Tokenizer`,
/// which hands back a coarse part of speech and none of IPAdic's
/// features; attaching endings to their verbs needs those.
public final class MecabAnalyzer: JapaneseAnalyzer, @unchecked Sendable {
    public enum Failure: Error { case dictionaryNotOpened(String) }

    public let name = "mecab-ipadic"

    // A MeCab tagger is not safe to share between threads; one lock
    // around each parse is.
    private let tagger: OpaquePointer
    private let lock = NSLock()
    private let fallback: SystemAnalyzer?

    /// Opens the dictionary. It is mapped into memory, not read, so this
    /// is quick and the memory stays with the system.
    public init(dictionary url: URL) throws {
        // MeCab splits its arguments at spaces; its Mecab-Swift fork
        // turns %20 back into a space, and nothing else.
        let path = url.path.replacingOccurrences(of: " ", with: "%20")
        guard let tagger = mecab_new2("-d \(path)") else {
            throw Failure.dictionaryNotOpened(String(cString: mecab_strerror(nil)))
        }
        self.tagger = tagger
        #if canImport(CoreFoundation)
        fallback = SystemAnalyzer()
        #else
        fallback = nil
        #endif
    }

    deinit { mecab_destroy(tagger) }

    public func analyze(_ line: String) -> [LyricToken] {
        // Composed form: a dictionary knows が, not か and a mark. The
        // character count is the same either way, so ranges still fit
        // the line as given.
        let chars = Array(line.precomposedStringWithCanonicalMapping)
        var tokens: [LyricToken] = []
        var attachNext = false
        for segment in LineSegmenter.segments(chars) {
            let previousEnd = tokens.last?.range.upperBound
            switch segment.kind {
            case .latin:
                var (token, opens) = LineSegmenter.latinToken(segment, previousEnd: previousEnd)
                if attachNext, previousEnd == segment.range.lowerBound { token.attach = true }
                tokens.append(token)
                attachNext = opens
            case .japanese:
                var previous: Morpheme?
                for m in morphemes(segment) {
                    let touching = previous.flatMap { $0.range.upperBound == m.range.lowerBound ? $0 : nil }
                    defer { previous = m }
                    guard
                        var mapped = IPAdicMapping.map(
                            m, previous: touching, unknownReading: { [fallback] in fallback?.reading(of: $0) })
                    else {
                        attachNext = false
                        continue
                    }
                    if attachNext, tokens.last?.range.upperBound == m.range.lowerBound {
                        mapped.tokens[0].attach = true
                    }
                    // Punctuation hangs on whatever is before it, a Latin word too.
                    if mapped.tokens[0].pos == .symbol, mapped.tokens[0].attach {
                        mapped.tokens[0].attach = tokens.last?.range.upperBound == m.range.lowerBound
                    }
                    tokens.append(contentsOf: mapped.tokens)
                    attachNext = mapped.attachNext
                }
            }
        }
        return tidy(tokens, line: String(chars))
    }

    private static let smallKana: Set<Unicode.Scalar> = [
        "ぁ", "ぃ", "ぅ", "ぇ", "ぉ", "ゃ", "ゅ", "ょ", "ゎ", "ァ", "ィ", "ゥ", "ェ", "ォ", "ャ", "ュ", "ョ", "ヮ",
    ]

    private static func isKatakana(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy { ($0.value >= 0x30A1 && $0.value <= 0x30FA) || $0.value == 0x30FC }
    }

    /// What the dictionary leaves untidy in lyrics.
    private func tidy(_ tokens: [LyricToken], line: String) -> [LyricToken] {
        var out: [LyricToken] = []
        var drawnOut = false
        for var token in tokens {
            let touches = out.last?.range.upperBound == token.range.lowerBound
            // What follows a drawn-out vowel is the rest of its word (すごー + い).
            if drawnOut, touches, token.pos != .symbol, token.pos != .particle { token.attach = true }
            drawnOut = false
            // A drawn-out vowel cut off as its own token (すごーい):
            // the long mark belongs to the sound before it.
            if token.surface.allSatisfy({ $0 == "ー" || $0 == "ｰ" }) {
                if touches, let last = out.last, !Kana.hasKana(last.reading) {
                    // After digits or Latin there is no vowel to draw out.
                    token.pos = .symbol
                    token.attach = true
                    out.append(token)
                } else if touches, var previous = out.popLast() {
                    previous.surface += token.surface
                    previous.reading += String(repeating: "ー", count: token.surface.count)
                    previous.range = previous.range.lowerBound..<token.range.upperBound
                    out.append(previous)
                    drawnOut = true
                }
                continue
            }
            // No word starts with a small kana: it finishes the sound
            // before it (とおり + ゃんせ is とおりゃんせ).
            if touches, let first = token.surface.unicodeScalars.first, Self.smallKana.contains(first),
                var previous = out.last, Kana.hasKana(previous.reading), previous.pos != .symbol
            {
                out.removeLast()
                previous.surface += token.surface
                previous.reading += token.reading
                previous.range = previous.range.lowerBound..<token.range.upperBound
                out.append(previous)
                continue
            }
            // A run of katakana is one word, however the dictionary
            // cut it (バレ + バレ, アッパ + レ).
            if touches, let previous = out.last, Self.isKatakana(previous.surface), Self.isKatakana(token.surface) {
                token.attach = true
            }
            // No word ends in っ before more kana: whatever touches it
            // is the rest of the word (ぼっ + ち).
            if touches, token.pos != .symbol, let previous = out.last, previous.pos != .symbol,
                previous.reading.hasSuffix("ッ") || previous.reading.hasSuffix("っ")
            {
                token.attach = true
            }
            out.append(token)
        }
        return readUnknown(out, line: line)
    }

    /// Kanji the dictionary has no reading for: ask the system, which
    /// may know the word whole (揺蕩う) where MeCab cut it into pieces.
    private func readUnknown(_ tokens: [LyricToken], line: String) -> [LyricToken] {
        guard let fallback, tokens.contains(where: { Kana.hasKanji($0.reading) }) else { return tokens }
        let system = fallback.analyze(line).filter { !Kana.hasKanji($0.reading) && Kana.hasKanji($0.surface) }
        guard !system.isEmpty else { return tokens }
        var out: [LyricToken] = []
        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            guard Kana.hasKanji(token.reading),
                let word = system.first(where: { $0.range.overlaps(token.range) }),
                let first = tokens.firstIndex(where: { $0.range.lowerBound == word.range.lowerBound }), first <= i,
                let last = tokens.firstIndex(where: { $0.range.upperBound == word.range.upperBound }), last >= i,
                first >= i - (tokens.count - out.count), out.count >= i - first
            else {
                out.append(token)
                i += 1
                continue
            }
            // Take back what was already passed on, and put the whole word in its place.
            out.removeLast(i - first)
            var merged = tokens[first]
            merged.surface = word.surface
            merged.reading = word.reading
            merged.range = word.range
            merged.needsReview = true
            merged.pos = first == last ? token.pos : .other
            out.append(merged)
            i = last + 1
        }
        return out
    }

    private func morphemes(_ segment: LineSegment) -> [Morpheme] {
        // Byte offset of each character, to turn MeCab's byte positions
        // back into character positions.
        var charAt: [Int: Int] = [:]
        var offset = 0
        for (i, ch) in segment.text.enumerated() {
            charAt[offset] = i
            offset += ch.utf8.count
        }
        charAt[offset] = segment.text.count

        lock.lock()
        defer { lock.unlock() }
        var out: [Morpheme] = []
        segment.text.withCString { base in
            var node = mecab_sparse_tonode(tagger, base)
            while let n = node {
                let p = n.pointee
                node = UnsafePointer(p.next)
                guard p.length > 0, let surfacePointer = p.surface else { continue }
                let start = surfacePointer - base
                let length = Int(p.length)
                guard let from = charAt[start], let to = charAt[start + length] else { continue }
                let surface = String(
                    decoding: UnsafeRawBufferPointer(start: surfacePointer, count: length), as: UTF8.self)
                let features = String(cString: p.feature).split(separator: ",", omittingEmptySubsequences: false)
                    .map(String.init)
                out.append(
                    Morpheme(
                        surface: surface, features: features,
                        range: (segment.range.lowerBound + from)..<(segment.range.lowerBound + to)))
            }
        }
        return out
    }
}
