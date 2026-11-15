import Foundation

/// Script tests and kana conversion, by Unicode scalar.
public enum Kana {
    /// Katakana to hiragana, by scalar offset for U+30A1 to U+30F6.
    /// The reference's `kata_to_hira`.
    public static func hiragana(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for c in s.unicodeScalars {
            if c.value >= 0x30A1, c.value <= 0x30F6, let h = Unicode.Scalar(c.value - 0x60) {
                out.append(h)
            } else {
                out.append(c)
            }
        }
        return String(out)
    }

    /// Hiragana to katakana, the other way round.
    public static func katakana(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for c in s.unicodeScalars {
            if c.value >= 0x3041, c.value <= 0x3096, let k = Unicode.Scalar(c.value + 0x60) {
                out.append(k)
            } else {
                out.append(c)
            }
        }
        return String(out)
    }

    /// Hiragana, katakana and the long mark: U+3041 to U+30FF.
    public static func isKana(_ c: Unicode.Scalar) -> Bool {
        c.value >= 0x3041 && c.value <= 0x30FF
    }

    /// Kana a reading may be made of: no middle dot, no iteration marks.
    public static func isReadingKana(_ c: Unicode.Scalar) -> Bool {
        (c.value >= 0x3041 && c.value <= 0x3096)
            || (c.value >= 0x30A1 && c.value <= 0x30FA)
            || c.value == 0x30FC
    }

    public static func isKanji(_ c: Unicode.Scalar) -> Bool {
        switch c.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF, 0x20000...0x2FA1F:
            true
        case 0x3005, 0x3006, 0x3007:  // 々 〆 〇
            true
        default:
            false
        }
    }

    public static func hasKana(_ s: String) -> Bool {
        s.unicodeScalars.contains(where: isKana)
    }

    public static func hasKanji(_ s: String) -> Bool {
        s.unicodeScalars.contains(where: isKanji)
    }

    public static func isAllReadingKana(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy(isReadingKana)
    }

    /// Kana or kanji anywhere in the text.
    public static func hasJapanese(_ s: String) -> Bool {
        s.unicodeScalars.contains { isKana($0) || isKanji($0) }
    }

    /// Whether lyrics are Japanese rather than Chinese: kanji alone is
    /// not enough, there has to be kana somewhere in the song.
    public static func isJapaneseLyrics(_ lines: [String]) -> Bool {
        lines.contains { line in
            line.unicodeScalars.contains {
                ($0.value >= 0x3041 && $0.value <= 0x3096) || ($0.value >= 0x30A1 && $0.value <= 0x30FA)
            }
        }
    }
}
