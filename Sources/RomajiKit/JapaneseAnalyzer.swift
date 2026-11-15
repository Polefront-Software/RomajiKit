import Foundation

/// Splits a lyric line into words with readings. MeCab with IPAdic, a
/// larger dictionary later, and the system tokenizer all sit behind
/// this, so they can be swapped and scored against each other.
public protocol JapaneseAnalyzer: Sendable {
    /// Shown in the scorer's report.
    var name: String { get }
    /// The line's tokens in order. Ranges count characters of `line`.
    /// Whitespace gets no token.
    func analyze(_ line: String) -> [LyricToken]
}

/// A stretch of a line that is all Japanese or all Latin.
struct LineSegment: Equatable {
    enum Kind { case japanese, latin }
    var kind: Kind
    var text: String
    /// In characters of the line.
    var range: Range<Int>
}

/// Cuts a line into Japanese and Latin stretches before any dictionary
/// sees it. A dictionary for Japanese breaks "Don't" into three; Latin
/// words go through whole instead.
enum LineSegmenter {
    private enum CharClass { case space, latin, digit, japanese }

    private static func classify(_ ch: Character) -> CharClass {
        guard let c = ch.unicodeScalars.first else { return .space }
        if c.properties.isWhitespace { return .space }
        switch c.value {
        case 0x30...0x39, 0xFF10...0xFF19:
            return .digit
        case 0x21...0x7E, 0x00A1...0x024F, 0x2010...0x2027, 0x2030...0x205E, 0xFF21...0xFF3A, 0xFF41...0xFF5A:
            return .latin
        default:
            return .japanese
        }
    }

    static func segments(_ chars: [Character]) -> [LineSegment] {
        // Digits belong with the Japanese they touch (100回目), and
        // with Latin otherwise (24 hours).
        var classes = chars.map(classify)
        var i = 0
        while i < classes.count {
            guard classes[i] == .digit else { i += 1; continue }
            var j = i
            while j < classes.count, classes[j] == .digit { j += 1 }
            let before = i > 0 ? classes[i - 1] : .space
            let after = j < classes.count ? classes[j] : .space
            let kind: CharClass = (before == .japanese || after == .japanese) ? .japanese : .latin
            for k in i..<j { classes[k] = kind }
            i = j
        }
        var out: [LineSegment] = []
        i = 0
        while i < classes.count {
            let c = classes[i]
            var j = i
            while j < classes.count, classes[j] == c { j += 1 }
            if c != .space {
                out.append(LineSegment(kind: c == .japanese ? .japanese : .latin, text: String(chars[i..<j]), range: i..<j))
            }
            i = j
        }
        return out
    }

    /// Full-width Latin letters and marks as their plain forms: ＦＬＹ is FLY.
    static func narrow(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for c in text.unicodeScalars {
            if c.value >= 0xFF01, c.value <= 0xFF5E, let plain = Unicode.Scalar(c.value - 0xFEE0) {
                out.append(plain)
            } else {
                out.append(c)
            }
        }
        return String(out)
    }

    private static let openers: Set<Character> = ["(", "[", "{", "“", "‘", "<"]

    /// A Latin stretch as a token: a word passes through as it is,
    /// punctuation hangs on the word before it. Returns whether the
    /// token after it should hang on this one (an opening bracket).
    static func latinToken(_ segment: LineSegment, previousEnd: Int?) -> (token: LyricToken, attachNext: Bool) {
        let isPunctuation = segment.text.unicodeScalars.allSatisfy {
            !$0.properties.isAlphabetic && !CharacterSet.decimalDigits.contains($0)
        }
        guard isPunctuation else {
            return (LyricToken(surface: segment.text, reading: narrow(segment.text), pos: .foreign, range: segment.range), false)
        }
        let touchesPrevious = previousEnd == segment.range.lowerBound
        var opens = segment.text.first.map(openers.contains) ?? false
        if !opens, let first = segment.text.first, first == "\"" || first == "'" {
            opens = !touchesPrevious
        }
        let token = LyricToken(
            surface: segment.text, reading: narrow(segment.text), pos: .symbol,
            attach: !opens && touchesPrevious, range: segment.range)
        return (token, opens)
    }
}
