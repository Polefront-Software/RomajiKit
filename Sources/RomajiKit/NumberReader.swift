import Foundation

/// Reads numbers aloud: digits and kanji numerals into kana, with the
/// sound changes a counter brings (100回 is ひゃっかい, 三本 is さんぼん,
/// 一人 is ひとり). A dictionary reads each numeral on its own and gets
/// these wrong, or has no reading for digits at all.
public struct NumberReader: Sendable {
    public init() {}

    // MARK: Plain numbers

    private static let digits = ["", "いち", "に", "さん", "よん", "ご", "ろく", "なな", "はち", "きゅう"]

    /// 0 to 9999 in hiragana.
    private static func belowTenThousand(_ n: Int) -> String {
        var out = ""
        let thousands = n / 1000, hundreds = n / 100 % 10, tens = n / 10 % 10, ones = n % 10
        switch thousands {
        case 0: break
        case 1: out += "せん"
        case 3: out += "さんぜん"
        case 8: out += "はっせん"
        default: out += digits[thousands] + "せん"
        }
        switch hundreds {
        case 0: break
        case 1: out += "ひゃく"
        case 3: out += "さんびゃく"
        case 6: out += "ろっぴゃく"
        case 8: out += "はっぴゃく"
        default: out += digits[hundreds] + "ひゃく"
        }
        switch tens {
        case 0: break
        case 1: out += "じゅう"
        default: out += digits[tens] + "じゅう"
        }
        out += digits[ones]
        return out
    }

    /// A whole number in hiragana, or nil when it is too large to name.
    /// Counted in 64 bits: a watch's own integers stop at two thousand million.
    public static func read(_ n: Int64) -> String? {
        guard n >= 0, n < 10_000_000_000_000_000 else { return nil }
        if n == 0 { return "ぜろ" }
        var out = ""
        let units: [(Int64, String)] = [(1_000_000_000_000, "ちょう"), (100_000_000, "おく"), (10_000, "まん"), (1, "")]
        var rest = n
        for (size, name) in units {
            let part = rest / size
            rest %= size
            guard part > 0 else { continue }
            var kana = belowTenThousand(Int(part))
            // 一千万 is いっせんまん, 一兆 is いっちょう; a bare 千 is せん.
            if !name.isEmpty, part / 1000 == 1 { kana = "いっ" + kana }
            if name == "ちょう", part % 10 == 1, part % 100 != 11 { kana = String(kana.dropLast(2)) + "いっ" }
            if name == "ちょう", part % 10 == 8 { kana = String(kana.dropLast(2)) + "はっ" }
            if name == "ちょう", part % 10 == 0, part % 100 != 0 { kana = String(kana.dropLast(1)) + "っ" }
            out += kana + name
        }
        return out
    }

    // MARK: Parsing

    private static let kanjiDigits: [Character: Int64] = [
        "〇": 0, "零": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
    ]
    private static let kanjiSmallUnits: [Character: Int64] = ["十": 10, "百": 100, "千": 1000]
    private static let kanjiLargeUnits: [Character: Int64] = ["万": 10_000, "億": 100_000_000, "兆": 1_000_000_000_000]

    /// The value of a run of digits, kanji numerals, or both (3万).
    static func value(_ text: String) -> Int64? {
        var total: Int64 = 0, section: Int64 = 0, current: Int64 = 0
        var sawDigitRun = false, any = false
        var positional: [Int64] = []
        for ch in text {
            guard let c = ch.unicodeScalars.first else { return nil }
            var digit: Int64?
            switch c.value {
            case 0x30...0x39: digit = Int64(c.value - 0x30)
            case 0xFF10...0xFF19: digit = Int64(c.value - 0xFF10)
            default: digit = kanjiDigits[ch]
            }
            if let digit {
                positional.append(digit)
                if positional.count > 16 { return nil }
                current = positional.reduce(0) { $0 * 10 + $1 }
                sawDigitRun = true
                any = true
            } else if let unit = kanjiSmallUnits[ch] {
                section += (sawDigitRun ? current : 1) * unit
                current = 0
                positional = []
                sawDigitRun = false
                any = true
            } else if let unit = kanjiLargeUnits[ch] {
                let part = section + current
                total += (part == 0 ? 1 : part) * unit
                section = 0
                current = 0
                positional = []
                sawDigitRun = false
                any = true
            } else if ch == "," || ch == "，" {
                continue
            } else {
                return nil
            }
        }
        return any ? total + section + current : nil
    }

    // MARK: Counters

    private enum HRow {
        /// 本 匹 杯: さんぼん, ろっぽん.
        case voiced
        /// 分 泊 発 歩: さんぷん, よんぷん.
        case plosive
    }

    private struct Counter {
        var kana: String
        var hRow: HRow = .voiced
        /// Whole readings for particular numbers (一人 is ひとり).
        var whole: [Int: String] = [:]
        /// The number's own reading when its last digit is this (四時 is よじ).
        var lastDigit: [Int: String] = [:]
        /// The counter's reading after ん where it is not regular (三階 is さんがい).
        var afterThree: String?
    }

    private static let counters: [String: Counter] = {
        var c: [String: Counter] = [:]
        func add(_ surfaces: String..., counter: Counter) { for s in surfaces { c[s] = counter } }
        add("人", counter: Counter(kana: "にん", whole: [1: "ひとり", 2: "ふたり"], lastDigit: [4: "よ"]))
        add("日", counter: Counter(
            kana: "にち",
            whole: [
                2: "ふつか", 3: "みっか", 4: "よっか", 5: "いつか", 6: "むいか", 7: "なのか", 8: "ようか",
                9: "ここのか", 10: "とおか", 14: "じゅうよっか", 20: "はつか", 24: "にじゅうよっか",
            ]))
        add("月", counter: Counter(kana: "がつ", lastDigit: [4: "し", 7: "しち", 9: "く"]))
        add("時", counter: Counter(kana: "じ", lastDigit: [4: "よ", 7: "しち", 9: "く"]))
        add("時間", counter: Counter(kana: "じかん", lastDigit: [4: "よ", 7: "しち", 9: "く"]))
        add("年", "年間", counter: Counter(kana: "ねん", lastDigit: [4: "よ"]))
        add("円", counter: Counter(kana: "えん", lastDigit: [4: "よ"]))
        add("歳", "才", counter: Counter(kana: "さい", whole: [20: "はたち"]))
        add("つ", counter: Counter(
            kana: "つ",
            whole: [
                1: "ひとつ", 2: "ふたつ", 3: "みっつ", 4: "よっつ", 5: "いつつ", 6: "むっつ", 7: "ななつ",
                8: "やっつ", 9: "ここのつ",
            ]))
        add("分", counter: Counter(kana: "ふん", hRow: .plosive))
        add("泊", counter: Counter(kana: "はく", hRow: .plosive))
        add("発", counter: Counter(kana: "はつ", hRow: .plosive))
        add("歩", counter: Counter(kana: "ほ", hRow: .plosive))
        add("本", counter: Counter(kana: "ほん"))
        add("匹", counter: Counter(kana: "ひき"))
        add("杯", counter: Counter(kana: "はい"))
        add("階", counter: Counter(kana: "かい", afterThree: "がい"))
        add("軒", counter: Counter(kana: "けん", afterThree: "げん"))
        add("足", counter: Counter(kana: "そく", afterThree: "ぞく"))
        for (surface, kana) in [
            ("回", "かい"), ("個", "こ"), ("度", "ど"), ("番", "ばん"), ("枚", "まい"), ("秒", "びょう"),
            ("週", "しゅう"), ("週間", "しゅうかん"), ("か月", "かげつ"), ("ヶ月", "かげつ"), ("ヵ月", "かげつ"),
            ("カ月", "かげつ"), ("ケ月", "かげつ"), ("箇月", "かげつ"), ("曲", "きょく"), ("冊", "さつ"),
            ("頭", "とう"), ("件", "けん"), ("着", "ちゃく"), ("通", "つう"), ("点", "てん"), ("台", "だい"),
            ("話", "わ"), ("倍", "ばい"), ("代", "だい"), ("世紀", "せいき"), ("号", "ごう"), ("行", "ぎょう"),
            ("文字", "もじ"), ("輪", "りん"), ("滴", "てき"), ("キロ", "きろ"), ("センチ", "せんち"),
            ("メートル", "めーとる"), ("パーセント", "ぱーせんと"), ("ページ", "ぺーじ"), ("％", "ぱーせんと"),
            ("%", "ぱーせんと"), ("位", "い"), ("番目", "ばんめ"), ("回目", "かいめ"), ("度目", "どめ"),
            ("秒間", "びょうかん"), ("日間", "にちかん"), ("光年", "こうねん"),
        ] {
            c[surface] = Counter(kana: kana)
        }
        return c
    }()

    private static let kRow: Set<Character> = ["か", "き", "く", "け", "こ"]
    private static let sRow: Set<Character> = ["さ", "し", "す", "せ", "そ"]
    private static let tRow: Set<Character> = ["た", "ち", "つ", "て", "と"]
    private static let hRow: [Character: (voiced: Character, plosive: Character)] = [
        "は": ("ば", "ぱ"), "ひ": ("び", "ぴ"), "ふ": ("ぶ", "ぷ"), "へ": ("べ", "ぺ"), "ほ": ("ぼ", "ぽ"),
    ]
    private static let pRow: Set<Character> = ["ぱ", "ぴ", "ぷ", "ぺ", "ぽ"]

    /// A number with its counter, in hiragana. `n` nil means 何.
    /// `bareUnit`: the number is written as a unit alone (万年 is まんねん).
    static func read(_ n: Int64?, counter surface: String, bareUnit: Bool = false) -> String? {
        guard let counter = counters[surface] else { return nil }
        guard let n else {
            // 何本 is なんぼん, 何分 is なんぷん.
            return "なん" + afterN(counter)
        }
        if let whole = Int(exactly: n).flatMap({ counter.whole[$0] }) { return whole }
        if surface == "つ" { return n == 10 ? "とお" : nil }
        guard var number = read(n) else { return nil }
        if bareUnit, number.hasPrefix("いち") { number = String(number.dropFirst(2)) }
        var tail = counter.kana
        guard let initial = tail.first else { return nil }
        let last = Int(n % 10)

        // What the number ends in, as the sound that meets the counter.
        enum Ending { case one, three, four, six, eight, ten, hundred, thousand, tenThousand, other }
        let ending: Ending
        switch last {
        case 1: ending = .one
        case 3: ending = .three
        case 4: ending = .four
        case 6: ending = .six
        case 8: ending = .eight
        case 0:
            if n % 100 != 0 { ending = .ten }
            else if n % 1000 != 0 { ending = .hundred }
            else if n % 10_000 != 0 { ending = .thousand }
            else if n % 100_000_000 != 0 { ending = .tenThousand }
            else { ending = .other }
        default: ending = .other
        }

        if let special = counter.lastDigit[last] {
            number = String(number.dropLast(digits[last].count)) + special
            return number + tail
        }

        // いち, ろく, はち, じゅう and ひゃく all lose their last kana to っ.
        func geminate() { number = String(number.dropLast()) + "っ" }
        let k = kRow.contains(initial), s = sRow.contains(initial), t = tRow.contains(initial)
        let h = hRow[initial], p = pRow.contains(initial)
        if h != nil {
            switch ending {
            case .one, .six, .eight, .ten, .hundred:
                geminate()
                tail = String(h!.plosive) + tail.dropFirst()
            case .three, .thousand, .tenThousand:
                tail = afterN(counter)
            case .four:
                if counter.hRow == .plosive { tail = String(h!.plosive) + tail.dropFirst() }
            case .other: break
            }
        } else if k || p {
            switch ending {
            case .one, .six, .eight, .ten, .hundred: geminate()
            case .three: if let voiced = counter.afterThree { tail = voiced }
            default: break
            }
        } else if s || t {
            switch ending {
            case .one, .eight, .ten: geminate()
            case .three: if let voiced = counter.afterThree { tail = voiced }
            default: break
            }
        }
        return number + tail
    }

    /// The counter as it sounds after ん.
    private static func afterN(_ counter: Counter) -> String {
        if let voiced = counter.afterThree { return voiced }
        guard let initial = counter.kana.first, let h = hRow[initial] else { return counter.kana }
        return String(counter.hRow == .voiced ? h.voiced : h.plosive) + counter.kana.dropFirst()
    }

    // MARK: Tokens

    private static let whatUnits = ["何十": "ナンジュウ", "何百": "ナンビャク", "何千": "ナンゼン", "何万": "ナンマン"]

    /// Joins each number to its counter and gives the pair one reading.
    /// A number the reader cannot name is marked for review.
    public func apply(_ tokens: [LyricToken]) -> [LyricToken] {
        var out: [LyricToken] = []
        var i = 0
        while i < tokens.count {
            guard tokens[i].pos == .number else {
                out.append(tokens[i])
                i += 1
                continue
            }
            // The whole run of numerals that touch each other.
            var j = i + 1
            while j < tokens.count, tokens[j].pos == .number, tokens[j].range.lowerBound == tokens[j - 1].range.upperBound {
                j += 1
            }
            let run = Array(tokens[i..<j])
            let surface = run.map(\.surface).joined()
            let isDigits = surface.unicodeScalars.contains { (0x30...0x39).contains($0.value) || (0xFF10...0xFF19).contains($0.value) }
            let isWhat = surface == "何"
            let value = isWhat ? nil : Self.value(surface)
            let bareUnit = surface.first.map { "万億兆".contains($0) } ?? false
            var merged = run[0]
            merged.surface = surface
            merged.range = run[0].range.lowerBound..<run[run.count - 1].range.upperBound

            // A counter right after it: one or two tokens (回, 回目).
            var counterLength = 0
            var counterReading: String?
            if isWhat || value != nil {
                for length in [2, 1] where j + length <= tokens.count {
                    let next = Array(tokens[j..<(j + length)])
                    guard next[0].range.lowerBound == merged.range.upperBound,
                        zip(next, next.dropFirst()).allSatisfy({ $0.range.upperBound == $1.range.lowerBound })
                    else { continue }
                    if let reading = Self.read(value, counter: next.map(\.surface).joined(), bareUnit: bareUnit) {
                        counterLength = length
                        counterReading = reading
                        break
                    }
                }
            }

            if let counterReading {
                let counterTokens = tokens[j..<(j + counterLength)]
                merged.surface += counterTokens.map(\.surface).joined()
                merged.range = merged.range.lowerBound..<counterTokens.last!.range.upperBound
                merged.reading = Kana.katakana(counterReading)
                merged.pos = .noun
                merged.needsReview = false
                // 一日 is いちにち as a length of time and ついたち as a date.
                if merged.surface == "一日" || merged.surface == "1日" || merged.surface == "１日" {
                    merged.candidates = ["ツイタチ"]
                }
                out.append(merged)
                i = j + counterLength
                continue
            }

            if let unit = Self.whatUnits[surface] {
                // 何百 is なんびゃく.
                merged.reading = unit
                out.append(merged)
            } else if let value, isDigits || run.count > 1 {
                // Digits, or several numerals: read as one number.
                // 007 and the like are read digit by digit.
                let leadingZero = surface.count > 1 && (surface.first == "0" || surface.first == "０")
                if !leadingZero, var reading = Self.read(value) {
                    if bareUnit, reading.hasPrefix("いち") { reading = String(reading.dropFirst(2)) }
                    merged.reading = Kana.katakana(reading)
                    merged.needsReview = false
                } else {
                    merged.reading = Kana.katakana(surface.compactMap { ch -> String? in
                        guard let d = Self.value(String(ch)) else { return nil }
                        return d == 0 ? "ぜろ" : Self.digits[Int(d)]
                    }.joined())
                    merged.needsReview = true
                }
                out.append(merged)
            } else if isDigits {
                // Digits the reader cannot name as one number: each
                // token on its own, digit by digit, marked.
                for var token in run {
                    let spoken = token.surface.compactMap { ch -> String? in
                        guard let d = Self.value(String(ch)), d < 10 else { return nil }
                        return d == 0 ? "ぜろ" : Self.digits[Int(d)]
                    }.joined()
                    if !Kana.hasKana(token.reading), !spoken.isEmpty {
                        token.reading = Kana.katakana(spoken)
                        token.needsReview = true
                    }
                    out.append(token)
                }
            } else {
                // A single kanji numeral with no counter the reader
                // knows: the dictionary's reading stands.
                out.append(contentsOf: run)
            }
            i = j
        }
        return out
    }
}
