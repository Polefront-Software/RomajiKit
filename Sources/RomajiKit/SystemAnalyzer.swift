#if canImport(CoreFoundation)
import CoreFoundation
import Foundation

/// The system's own tokenizer. It knows readings but not grammar, so
/// endings are not joined to their verbs and particles are guessed from
/// their spelling. For an instant preview, and for words MeCab's
/// dictionary does not know; never the main analyzer.
public struct SystemAnalyzer: JapaneseAnalyzer {
    public let name = "system-tokenizer"

    public init() {}

    public func analyze(_ line: String) -> [LyricToken] {
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
                attachNext = false
                for (surface, range, latin) in words(segment.text) {
                    let lineRange = (segment.range.lowerBound + range.lowerBound)..<(segment.range.lowerBound + range.upperBound)
                    let reading: String
                    var pos = PartOfSpeech.noun
                    var needsReview = false
                    var attach = false
                    if Kana.isAllReadingKana(surface) {
                        reading = Kana.katakana(surface)
                        if ["は", "へ", "を", "が", "に", "の", "と", "も", "で"].contains(surface) { pos = .particle }
                    } else if !Kana.hasJapanese(surface) {
                        reading = surface
                        let isSymbol = !surface.unicodeScalars.contains {
                            $0.properties.isAlphabetic || CharacterSet.decimalDigits.contains($0)
                        }
                        pos = isSymbol ? .symbol : .number
                        attach = isSymbol && tokens.last?.range.upperBound == lineRange.lowerBound
                    } else if let kana = latin.flatMap(Self.katakana(fromLatin:)) {
                        reading = kana
                    } else {
                        reading = surface
                        needsReview = true
                    }
                    tokens.append(
                        LyricToken(
                            surface: surface, reading: reading, pos: pos, attach: attach,
                            range: lineRange, needsReview: needsReview))
                }
            }
        }
        return tokens
    }

    /// The reading of one word, in katakana, or nil when the system has none.
    public func reading(of word: String) -> String? {
        let parts = words(word)
        var out = ""
        for (surface, _, latin) in parts {
            if Kana.isAllReadingKana(surface) {
                out += Kana.katakana(surface)
            } else if let kana = latin.flatMap(Self.katakana(fromLatin:)) {
                out += kana
            } else {
                return nil
            }
        }
        return out.isEmpty ? nil : out
    }

    /// Words with their character ranges and the system's Latin transcription.
    private func words(_ text: String) -> [(String, Range<Int>, String?)] {
        let ns = text as NSString
        let cf = text as CFString
        guard
            let tokenizer = CFStringTokenizerCreate(
                kCFAllocatorDefault, cf, CFRangeMake(0, ns.length), kCFStringTokenizerUnitWordBoundary,
                Locale(identifier: "ja") as CFLocale)
        else { return [] }
        // UTF-16 offset to character offset.
        var charAt: [Int: Int] = [:]
        var offset = 0
        for (i, ch) in text.enumerated() {
            charAt[offset] = i
            offset += ch.utf16.count
        }
        charAt[offset] = text.count

        var out: [(String, Range<Int>, String?)] = []
        while !CFStringTokenizerAdvanceToNextToken(tokenizer).isEmpty {
            let r = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            guard r.length > 0, let from = charAt[r.location], let to = charAt[r.location + r.length] else { continue }
            let surface = ns.substring(with: NSRange(location: r.location, length: r.length))
            if surface.unicodeScalars.allSatisfy(\.properties.isWhitespace) { continue }
            let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription)
                as? String
            out.append((surface, from..<to, latin))
        }
        return out
    }

    private static func katakana(fromLatin latin: String) -> String? {
        guard let kana = latin.applyingTransform(.latinToKatakana, reverse: false), Kana.isAllReadingKana(kana) else {
            return nil
        }
        return kana
    }
}
#endif
