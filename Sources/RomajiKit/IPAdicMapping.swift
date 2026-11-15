import Foundation

/// One morpheme as MeCab gives it, before it becomes a `LyricToken`.
struct Morpheme {
    var surface: String
    /// IPAdic's comma-separated features: part of speech (0 to 3),
    /// conjugation (4, 5), base form (6), reading (7), pronunciation (8).
    /// A word the dictionary does not know has only the first seven.
    var features: [String]
    var range: Range<Int>

    func feature(_ i: Int) -> String { i < features.count ? features[i] : "*" }
}

/// IPAdic's features turned into what the renderer needs: a part of
/// speech, and whether the word is written onto the one before it.
enum IPAdicMapping {
    /// Conjunctive particles written onto the verb: 待って, 行けば.
    private static let attachedConjunctive: Set<String> = ["て", "で", "ば", "たり", "だり", "ながら", "つつ", "ちゃ", "じゃ"]

    /// いる after て, and the contractions that swallow the て.
    private static let progressive: Set<String> = ["いる", "る", "てる", "でる", "とく", "どく", "ちゃう", "じゃう", "おる"]

    struct Mapped {
        var tokens: [LyricToken]
        /// The token after this one hangs on it (a prefix, an opening bracket).
        var attachNext = false
    }

    /// `previous` is the morpheme before this one, when it touches it.
    static func map(_ m: Morpheme, previous: Morpheme?, unknownReading: (String) -> String?) -> Mapped? {
        let f0 = m.feature(0)
        let f1 = m.feature(1)
        var pos = PartOfSpeech.other
        var attach = false
        var attachNext = false

        switch f0 {
        case "記号":
            // A space or a middle dot only parts two words.
            if f1 == "空白" || m.surface == "・" { return nil }
            pos = .symbol
            if f1 == "括弧開" { attachNext = true } else { attach = true }
        case "助詞":
            pos = .particle
            attach = f1 == "接続助詞" && attachedConjunctive.contains(m.surface)
        case "助動詞":
            pos = .aux
            // The copula stands apart (suki da, kirei desu); な and the
            // rest are endings.
            // IPAdic tells the copula だ from the past だ (叫んだ) by
            // its conjugation type. After ん it is one word: なんだ.
            let type = m.feature(4)
            let copula = (type == "特殊・ダ" || type == "特殊・デス") && m.surface != "な"
            attach = !copula || (previous?.surface == "ん" && previous?.feature(0) == "名詞")
        case "動詞":
            pos = .verb
            // A helper verb is one word with a verb stem (歩き出す) and
            // with て when it is いる or one of its short forms
            // (降っている, 愛してる); after て otherwise it stands apart
            // (たたんで しまう, 飛んで いけ).
            if f1 == "接尾" {
                attach = true
            } else if f1 == "非自立" {
                let afterTe = previous?.feature(1) == "接続助詞"
                attach = afterTe ? progressive.contains(m.feature(6)) : true
            }
        case "形容詞":
            pos = .adj
            // 食べやすい is one word; してほしい is two.
            attach = f1 == "接尾" || (f1 == "非自立" && previous?.feature(0) == "動詞")
        case "名詞":
            switch f1 {
            case "代名詞": pos = .pron
            case "数": pos = .number
            case "接尾":
                pos = .noun
                attach = true
            case "非自立":
                pos = .noun
                attach = m.surface == "ん"
            default: pos = .noun
            }
        case "副詞": pos = .adv
        case "連体詞": pos = .adnominal
        case "接続詞": pos = .conj
        case "感動詞", "フィラー": pos = .interj
        case "接頭詞":
            pos = .prefix
            attachNext = true
        default: pos = .other
        }

        // A suffix or an ending needs a word to hang on.
        if attach, pos != .symbol {
            if let previous {
                let p0 = previous.feature(0)
                if p0 == "記号" || (p0 == "助詞" && pos == .noun) { attach = false }
            } else {
                attach = false
            }
        }

        var reading = m.feature(7)
        var needsReview = false
        if reading == "*" || reading.isEmpty {
            if pos == .symbol || !Kana.hasJapanese(m.surface) {
                reading = m.surface
            } else if Kana.isAllReadingKana(m.surface) {
                reading = Kana.katakana(m.surface)
            } else {
                // Kanji the dictionary does not know.
                reading = unknownReading(m.surface) ?? m.surface
                needsReview = true
            }
        }
        if pos == .symbol { reading = m.surface }

        let token = LyricToken(
            surface: m.surface, reading: reading, pos: pos, attach: attach,
            range: m.range, needsReview: needsReview)

        // こんにちは, では: the last は is the particle and is said wa.
        // The dictionary's pronunciation field knows; split it off so
        // the renderer treats it as the particle it is.
        let pron = m.feature(8)
        if pos != .symbol, m.surface.count > 1, reading.count > 1, pron.count == reading.count,
            let lastSurface = m.surface.last, lastSurface == "は" || lastSurface == "へ",
            (reading.hasSuffix("ハ") && pron.hasSuffix("ワ")) || (reading.hasSuffix("ヘ") && pron.hasSuffix("エ"))
        {
            var stem = token
            stem.surface = String(m.surface.dropLast())
            stem.reading = String(reading.dropLast())
            stem.range = m.range.lowerBound..<(m.range.upperBound - 1)
            let particle = LyricToken(
                surface: String(lastSurface), reading: String(reading.suffix(1)), pos: .particle,
                attach: true, range: (m.range.upperBound - 1)..<m.range.upperBound)
            return Mapped(tokens: [stem, particle], attachNext: attachNext)
        }
        return Mapped(tokens: [token], attachNext: attachNext)
    }
}
