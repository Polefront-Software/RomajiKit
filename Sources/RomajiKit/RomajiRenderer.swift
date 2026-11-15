import Foundation

/// Kana to romaji. A port of `TestSupport/reference/romaji.py`, line for
/// line; `TestSupport/fixtures/renderer_cases.json` is the spec. To
/// change what this does, change the reference and the fixture first.
///
/// Python walks strings by code point, so this walks Unicode scalars,
/// never Characters.
public enum RomajiRenderer {
    enum LongVowel { case kana, macron, circumflex }

    struct Style {
        var long: LongVowel
        /// How っ before ch is written: "tch", "cch", or "tt" (Kunrei,
        /// where ち is ti and never starts with ch).
        var sokuonCh: String
        var kunrei: Bool
        var wo: String
    }

    static func style(_ preset: RomajiPreset) -> Style {
        switch preset {
        case .singalong: Style(long: .kana, sokuonCh: "tch", kunrei: false, wo: "o")
        case .learner: Style(long: .macron, sokuonCh: "tch", kunrei: false, wo: "o")
        case .official: Style(long: .kana, sokuonCh: "cch", kunrei: false, wo: "o")
        case .kunrei: Style(long: .circumflex, sokuonCh: "tt", kunrei: true, wo: "o")
        }
    }

    static let base: [String: String] = [
        "あ": "a", "い": "i", "う": "u", "え": "e", "お": "o",
        "か": "ka", "き": "ki", "く": "ku", "け": "ke", "こ": "ko",
        "さ": "sa", "し": "shi", "す": "su", "せ": "se", "そ": "so",
        "た": "ta", "ち": "chi", "つ": "tsu", "て": "te", "と": "to",
        "な": "na", "に": "ni", "ぬ": "nu", "ね": "ne", "の": "no",
        "は": "ha", "ひ": "hi", "ふ": "fu", "へ": "he", "ほ": "ho",
        "ま": "ma", "み": "mi", "む": "mu", "め": "me", "も": "mo",
        "や": "ya", "ゆ": "yu", "よ": "yo",
        "ら": "ra", "り": "ri", "る": "ru", "れ": "re", "ろ": "ro",
        "わ": "wa", "ゐ": "i", "ゑ": "e", "を": "o",
        "が": "ga", "ぎ": "gi", "ぐ": "gu", "げ": "ge", "ご": "go",
        "ざ": "za", "じ": "ji", "ず": "zu", "ぜ": "ze", "ぞ": "zo",
        "だ": "da", "ぢ": "ji", "づ": "zu", "で": "de", "ど": "do",
        "ば": "ba", "び": "bi", "ぶ": "bu", "べ": "be", "ぼ": "bo",
        "ぱ": "pa", "ぴ": "pi", "ぷ": "pu", "ぺ": "pe", "ぽ": "po",
        "ゔ": "vu",
        "ぁ": "a", "ぃ": "i", "ぅ": "u", "ぇ": "e", "ぉ": "o",
        "ゃ": "ya", "ゅ": "yu", "ょ": "yo",
        "ゎ": "wa", "ゕ": "ka", "ゖ": "ke",
        "ヷ": "va", "ヸ": "vi", "ヹ": "ve", "ヺ": "vo",
    ]

    /// Two-kana combinations: yōon and loanword sounds.
    static let combo: [String: String] = {
        var c: [String: String] = [:]
        for (k, r) in ["き": "k", "ぎ": "g", "に": "n", "ひ": "h", "び": "b", "ぴ": "p", "み": "m", "り": "r"] {
            c[k + "ゃ"] = r + "ya"
            c[k + "ゅ"] = r + "yu"
            c[k + "ょ"] = r + "yo"
        }
        for (k, r) in ["し": "sh", "ち": "ch", "じ": "j", "ぢ": "j"] {
            c[k + "ゃ"] = r + "a"
            c[k + "ゅ"] = r + "u"
            c[k + "ょ"] = r + "o"
            c[k + "ぇ"] = r + "e"
        }
        c.merge([
            "てぃ": "ti", "でぃ": "di", "とぅ": "tu", "どぅ": "du", "てゅ": "tyu", "でゅ": "dyu",
            "ふぁ": "fa", "ふぃ": "fi", "ふぇ": "fe", "ふぉ": "fo", "ふゅ": "fyu",
            "ゔぁ": "va", "ゔぃ": "vi", "ゔぇ": "ve", "ゔぉ": "vo",
            "うぃ": "wi", "うぇ": "we", "うぉ": "wo", "つぁ": "tsa", "つぃ": "tsi",
            "つぇ": "tse", "つぉ": "tso", "いぇ": "ye", "くぁ": "kwa", "くゎ": "kwa", "ぐぁ": "gwa",
        ]) { _, new in new }
        return c
    }()

    static let punct: [String: String] = [
        "、": ",", "。": ".", "「": "\"", "」": "\"", "！": "!", "？": "?", "　": " ", "…": "...",
        "『": "\"", "』": "\"", "（": "(", "）": ")", "【": "[", "】": "]", "〜": "~", "～": "~",
        "，": ",", "．": ".", "：": ":", "；": ";",
    ]

    static let kunrei: [String: String] = [
        "shi": "si", "chi": "ti", "tsu": "tu", "fu": "hu", "ji": "zi",
        "sha": "sya", "shu": "syu", "sho": "syo", "cha": "tya", "chu": "tyu",
        "cho": "tyo", "ja": "zya", "ju": "zyu", "jo": "zyo",
    ]

    static let vowels: Set<Unicode.Scalar> = ["a", "e", "i", "o", "u"]
    static let macron: [Unicode.Scalar: String] = ["a": "ā", "i": "ī", "u": "ū", "e": "ē", "o": "ō"]
    static let circumflex: [Unicode.Scalar: String] = ["a": "â", "i": "î", "u": "û", "e": "ê", "o": "ô"]

    // Markers for っ, ん and ー among the syllables. A kana unit is one
    // or two scalars, so none can be mistaken for a marker.
    static let q = "<Q>"
    static let n = "<N>"
    static let l = "<L>"

    /// Split hiragana into syllable units, longest match first.
    static func kanaUnits(_ h: [Unicode.Scalar]) -> [String] {
        var out: [String] = []
        var i = 0
        while i < h.count {
            if i + 1 < h.count {
                let two = string([h[i], h[i + 1]])
                if combo[two] != nil {
                    out.append(two)
                    i += 2
                    continue
                }
            }
            out.append(string([h[i]]))
            i += 1
        }
        return out
    }

    static func unitRomaji(_ u: String, _ p: Style) -> String {
        guard var r = combo[u] ?? base[u] else {
            // Not kana (Latin, punctuation): passes through.
            return punct[u] ?? u
        }
        if p.kunrei { r = kunrei[r] ?? r }
        return r
    }

    /// One token's romaji. `nextHead` is the romaji of the token after
    /// it when that token is attached to this one, else empty.
    public static func renderToken(
        reading: String, pos: PartOfSpeech, preset: RomajiPreset, nextHead: String = ""
    ) -> String {
        renderToken(reading: reading, pos: pos, style: style(preset), nextHead: nextHead)
    }

    static func renderToken(reading: String, pos: PartOfSpeech, style p: Style, nextHead: String) -> String {
        let h = Array(Kana.hiragana(reading).unicodeScalars)
        // A token with no kana (Latin words, digits, punctuation) passes
        // through: its vowels are never merged into long vowels.
        if !h.contains(where: Kana.isKana) {
            return h.map { punct[string([$0])] ?? string([$0]) }.joined()
        }
        // Particles by grammatical role, not by kana.
        if pos == .particle, h.count == 1 {
            if h[0] == "は" { return "wa" }
            if h[0] == "へ" { return "e" }
            if h[0] == "を" { return p.wo }
        }
        var syl: [String] = []
        for u in kanaUnits(h) {
            switch u {
            case "っ": syl.append(q)
            case "ん": syl.append(n)
            case "ー": syl.append(l)
            default: syl.append(unitRomaji(u, p))
            }
        }
        // Verb and adjective endings: a final う or い is not a long vowel.
        let protectLast = (pos == .verb || pos == .adj) && syl.count >= 2
        var out: [String] = []
        for (i, s) in syl.enumerated() {
            let nxt = i + 1 < syl.count ? syl[i + 1] : nextHead
            let first = nxt.unicodeScalars.first
            let prev = out.last ?? ""
            let prevLast = prev.unicodeScalars.last
            if s == q {
                if nxt.hasPrefix("ch") {
                    out.append(p.sokuonCh == "tch" ? "t" : "c")
                } else if let first, first.isASCII, first.properties.isAlphabetic,
                    !vowels.contains(lowercased(first))
                {
                    out.append(string([first]))
                } else {
                    out.append("")  // word-final っ, as in an exclamation: dropped
                }
                continue
            }
            if s == n {
                if let first, vowels.contains(first) || first == "y" {
                    out.append("n'")
                } else {
                    out.append("n")
                }
                continue
            }
            if s == l {
                let v: Unicode.Scalar? = prevLast.flatMap { vowels.contains($0) ? $0 : nil }
                if p.long == .kana {
                    out.append(v.map { string([$0]) } ?? "")
                } else if let v {
                    let table = p.long == .macron ? macron : circumflex
                    out[out.count - 1] = dropLast(prev) + table[v]!
                }
                continue
            }
            // Long vowels written with kana: oo and ou, uu, aa. Never ei or ii.
            if p.long != .kana, !prev.isEmpty, s == "u" || s == "o" || s == "a",
                !(protectLast && i == syl.count - 1), let v = prevLast
            {
                if (v == "o" && (s == "o" || s == "u")) || (v == "u" && s == "u") || (v == "a" && s == "a") {
                    let table = p.long == .macron ? macron : circumflex
                    out[out.count - 1] = dropLast(prev) + table[v]!
                    continue
                }
            }
            out.append(s)
        }
        return out.joined()
    }

    /// A whole line: each token's romaji, and the tokens joined into
    /// words. `readings` are the resolved readings, one per token.
    public static func renderLine(
        tokens: [LyricToken], readings: [String], preset: RomajiPreset
    ) -> (text: String, tokens: [String]) {
        precondition(tokens.count == readings.count)
        let p = style(preset)
        // Right to left, so a token-final っ can see the next token's sound.
        var rendered = [String](repeating: "", count: tokens.count)
        var nextHead = ""
        for idx in stride(from: tokens.count - 1, through: 0, by: -1) {
            rendered[idx] = renderToken(reading: readings[idx], pos: tokens[idx].pos, style: p, nextHead: nextHead)
            // っ and ん look across a boundary only into attached endings
            // (待っ + て), never into a separate word (瞬間 + へ stays
            // "shunkan e").
            nextHead = tokens[idx].attach ? rendered[idx] : ""
        }
        // Volitional う on its stem (行こ + う) is one long ō with the
        // stem's o: ikō, omoō. Written out as "ou" where long vowels
        // stay as written.
        if p.long != .kana, tokens.count > 1 {
            let table = p.long == .macron ? macron : circumflex
            for idx in 1..<tokens.count {
                let t = tokens[idx]
                if t.attach, t.pos == .aux, Kana.hiragana(readings[idx]) == "う", rendered[idx - 1].hasSuffix("o") {
                    rendered[idx - 1] = dropLast(rendered[idx - 1]) + table["o"]!
                    rendered[idx] = ""
                }
            }
        }
        var words: [String] = []
        for (t, r) in zip(tokens, rendered) {
            if t.attach, !words.isEmpty {
                words[words.count - 1] += r
            } else {
                words.append(r)
            }
        }
        return (words.joined(separator: " "), rendered)
    }

    private static func string(_ scalars: [Unicode.Scalar]) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    private static func dropLast(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.dropLast()))
    }

    private static func lowercased(_ c: Unicode.Scalar) -> Unicode.Scalar {
        (c.value >= 0x41 && c.value <= 0x5A) ? Unicode.Scalar(c.value + 0x20)! : c
    }
}
