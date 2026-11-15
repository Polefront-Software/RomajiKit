import Foundation
import Testing
@testable import RomajiKit

@Suite struct NumberReaderTests {
    @Test(arguments: [
        (0, "ぜろ"), (10, "じゅう"), (100, "ひゃく"), (300, "さんびゃく"), (600, "ろっぴゃく"), (800, "はっぴゃく"),
        (1000, "せん"), (3000, "さんぜん"), (8000, "はっせん"), (10_000, "いちまん"), (1999, "せんきゅうひゃくきゅうじゅうきゅう"),
        (10_000_000, "いっせんまん"), (123_456_789, "いちおくにせんさんびゃくよんじゅうごまんろくせんななひゃくはちじゅうきゅう"),
    ])
    func plainNumbers(n: Int, kana: String) {
        #expect(NumberReader.read(Int64(n)) == kana)
    }

    @Test(arguments: [
        ("100回", "ひゃっかい"), ("1回", "いっかい"), ("6回", "ろっかい"), ("8回", "はっかい"), ("10回", "じゅっかい"),
        ("3本", "さんぼん"), ("1本", "いっぽん"), ("6本", "ろっぽん"), ("2本", "にほん"), ("千本", "せんぼん"),
        ("3分", "さんぷん"), ("4分", "よんぷん"), ("10分", "じゅっぷん"), ("1人", "ひとり"), ("二人", "ふたり"),
        ("4人", "よにん"), ("14人", "じゅうよにん"), ("3人", "さんにん"), ("二十歳", "はたち"), ("8歳", "はっさい"),
        ("4月", "しがつ"), ("7月", "しちがつ"), ("9月", "くがつ"), ("4時", "よじ"), ("9時", "くじ"),
        ("二日", "ふつか"), ("20日", "はつか"), ("15日", "じゅうごにち"), ("一日", "いちにち"), ("3階", "さんがい"),
        ("一つ", "ひとつ"), ("何本", "なんぼん"), ("何回", "なんかい"), ("万年", "まんねん"),
        ("一歩", "いっぽ"), ("３人", "さんにん"), ("十年", "じゅうねん"),
    ])
    func numbersWithCounters(text: String, kana: String) {
        let line = TestSupport.engine.romanize(line: text + "を")
        #expect(line.kana == kana + "を", "\(text)")
    }

    @Test func digitsAloneAndUnknown() {
        let engine = TestSupport.engine
        #expect(engine.romanize(line: "100の夢").text == "hyaku no yume")
        let odd = engine.romanize(line: "007の夢")
        #expect(odd.tokens.first?.needsReview == true)
        #expect(!Kana.hasJapanese(odd.text))
        // A lone kanji numeral keeps the dictionary's reading.
        #expect(engine.romanize(line: "千の風").kana == "せんのかぜ")
    }

    @Test func kanjiNumeralValues() {
        #expect(NumberReader.value("二十") == 20)
        #expect(NumberReader.value("三百六十五") == 365)
        #expect(NumberReader.value("3万") == 30_000)
        #expect(NumberReader.value("一億二千万") == 120_000_000)
        #expect(NumberReader.value("何") == nil)
    }
}

@Suite struct RubyParserTests {
    @Test func theFourSpellings() {
        let p = RubyParser.parse("|運命《さだめ》の人、未来(あした)へ、{宇宙|そら}の果て、夜空（よぞら）")
        #expect(p.text == "運命の人、未来へ、宇宙の果て、夜空")
        #expect(p.annotations.map(\.reading) == ["さだめ", "あした", "そら", "よぞら"])
        let chars = Array(p.text)
        #expect(p.annotations.map { String(chars[$0.range]) } == ["運命", "未来", "宇宙", "夜空"])
    }

    @Test func bracketsThatAreNotReadingsStay() {
        #expect(RubyParser.parse("(Yeah) 好きだよ（笑）").text == "(Yeah) 好きだよ（笑）")
        #expect(RubyParser.parse("ねえ(ねえ)").text == "ねえ(ねえ)")  // no kanji before it
        #expect(RubyParser.parse("a|b").text == "a|b")
        #expect(RubyParser.parse("{a}").text == "{a}")
        #expect(RubyParser.parse("夢《").text == "夢《")
    }

    @Test func rubyWinsAndClearsTheReviewMark() {
        let engine = TestSupport.engine
        let plain = engine.romanize(line: "運命の人")
        #expect(plain.text == "unmei no hito")
        #expect(plain.tokens[0].needsReview)
        #expect(plain.tokens[0].resolved.candidates.contains("サダメ"))
        let ruby = engine.romanize(line: "運命(さだめ)の人")
        #expect(ruby.displayText == "運命の人")
        #expect(ruby.text == "sadame no hito")
        #expect(ruby.tokens[0].resolved.source == .ruby)
        #expect(!ruby.tokens[0].needsReview)
    }

    @Test func rubyOnPartOfAWord() {
        let engine = TestSupport.engine
        #expect(engine.romanize(line: "見上(みあ)げた空").kana == "みあげたそら")
        #expect(engine.romanize(line: "花(はな)びら舞(ま)う").kana == "はなびらまう")
        // Furigana on each kanji of one word.
        #expect(engine.romanize(line: "夜(よ)空(ぞら)").kana == "よぞら")
        // Furigana on one kanji of two: the other keeps the dictionary's.
        #expect(engine.romanize(line: "夜(よ)空に").kana == "よぞらに")
        // Furigana over two of the analyzer's tokens.
        #expect(engine.romanize(line: "|二人《ふたり》で").kana == "ふたりで")
        #expect(engine.romanize(line: "{今日この頃|きょうこのごろ}").kana == "きょうこのごろ")
    }
}

@Suite struct AnalyzerTests {
    @Test(arguments: [
        ("涙を拭いて歩き出す", "namida o fuite arukidasu"),
        ("こんにちは、それでは行こう", "konnichiwa, soredewa ikou"),
        ("好きです。綺麗だった", "suki desu. kirei datta"),
        ("だって好きなんだもん", "datte sukinanda mon"),
        ("叫んだ、飛んだ", "sakenda, tonda"),
        ("君にKissして Don't stop", "kimi ni Kiss shite Don't stop"),
        ("(Yeah) I love you, baby! 好きだよ!", "(Yeah) I love you, baby! suki da yo!"),
        ("「愛してる」って言って", "\"aishiteru\" tte itte"),
        ("行った場所", "itta basho"),
        ("身体が震える", "karada ga furueru"),
        ("僕の側にいて", "boku no soba ni ite"),
        ("ひとりぼっちの夜", "hitoribotchi no yoru"),
        ("一日中ずっと", "ichinichijuu zutto"),
        ("やったー！", "yattaa!"),
        ("お茶を飲んで", "ocha o nonde"),
        ("東京タワーは綺麗だね", "toukyou tawaa wa kirei da ne"),
    ])
    func wordsAndEndings(line: String, romaji: String) {
        #expect(TestSupport.engine.romanize(line: line).text == romaji)
    }

    @Test func presets() {
        let engine = TestSupport.engine
        let line = "今日も東京で行こう"
        #expect(engine.romanize(line: line, preset: .singalong).text == "kyou mo toukyou de ikou")
        #expect(engine.romanize(line: line, preset: .learner).text == "kyō mo tōkyō de ikō")
        #expect(engine.romanize(line: line, preset: .kunrei).text == "kyô mo tôkyô de ikô")
        #expect(engine.romanize(line: "抹茶", preset: .official).text == "maccha")
    }

    @Test func linesWithoutJapanese() {
        let line = TestSupport.engine.romanize(line: "I love you")
        #expect(!line.hasJapanese)
        #expect(line.text == "I love you")
        #expect(line.tokens.isEmpty)
        #expect(Kana.isJapaneseLyrics(["我爱你", "永远"]) == false)
        #expect(Kana.isJapaneseLyrics(["Hello", "君が好き"]))
    }

    @Test func rangesFollowTheLine() {
        let line = TestSupport.engine.romanize(line: "君の 声が、聞こえる")
        let chars = Array(line.displayText)
        for t in line.tokens { #expect(String(chars[t.range]) == t.surface) }
        #expect(line.tokens.map(\.surface) == ["君", "の", "声", "が", "、", "聞こえる"])
        let romaji = Array(line.text)
        #expect(line.tokens.map { String(romaji[$0.romajiRange]) } == ["kimi", "no", "koe", "ga", ",", "kikoeru"])
    }

    @Test func wordsTheDictionaryDoesNotKnow() {
        // The system's tokenizer reads what IPAdic cannot; the word is marked.
        let line = TestSupport.engine.romanize(line: "燈が灯る")
        #expect(!Kana.hasJapanese(line.text))
        #expect(line.tokens.first?.needsReview == true)
    }

    @Test func systemAnalyzerStandsIn() {
        let engine = RomajiEngine(analyzer: SystemAnalyzer())
        let line = engine.romanize(line: "夜空に星が光る")
        #expect(!Kana.hasJapanese(line.text))
        #expect(line.kana == "よぞらにほしがひかる")
    }
}

@Suite struct OverrideStoreTests {
    let song = SongIdentity(musicBrainzRecordingID: nil, navidromeID: "song-1")

    @Test func identityPrefersMusicBrainz() {
        #expect(SongIdentity(musicBrainzRecordingID: "ABC", navidromeID: "1").key == "mbid:abc")
        #expect(SongIdentity(musicBrainzRecordingID: " ", navidromeID: "1").key == "nd:1")
    }

    @Test func aUserFixIsForThisSongOnly() async {
        let store = OverrideStore(fileURL: nil)
        let engine = RomajiEngine(analyzer: TestSupport.engine.analyzer, store: store)
        let lyrics = ["運命の人", "未来を信じて"]
        let hash = LyricsHash.make(lyrics)
        await store.set(ReadingOverride(line: 0, range: 0..<2, surface: "運命", reading: "さだめ", lyricsHash: hash), for: song)

        let lines = await engine.romanize(lyrics: lyrics, songID: song)
        #expect(lines[0].text == "sadame no hito")
        #expect(lines[0].tokens[0].resolved.source == .user)
        #expect(!lines[0].tokens[0].needsReview)
        #expect(lines[1].text == "mirai o shinjite")

        let other = await engine.romanize(lyrics: lyrics, songID: .navidrome("song-2"))
        #expect(other[0].text == "unmei no hito")
    }

    @Test func userBeatsRuby() async {
        let store = OverrideStore(fileURL: nil)
        let engine = RomajiEngine(analyzer: TestSupport.engine.analyzer, store: store)
        let lyrics = ["運命(さだめ)の人"]
        await store.set(
            ReadingOverride(line: 0, range: 0..<2, surface: "運命", reading: "うんめい", lyricsHash: LyricsHash.make(lyrics)), for: song)
        let lines = await engine.romanize(lyrics: lyrics, songID: song)
        #expect(lines[0].text == "unmei no hito")
        #expect(lines[0].tokens[0].resolved.candidates.contains("サダメ"))
    }

    @Test func changedLyricsKeepTheFixAndMarkIt() async {
        let store = OverrideStore(fileURL: nil)
        let engine = RomajiEngine(analyzer: TestSupport.engine.analyzer, store: store)
        let old = ["運命の人"]
        await store.set(ReadingOverride(line: 0, range: 0..<2, surface: "運命", reading: "さだめ", lyricsHash: LyricsHash.make(old)), for: song)

        // Another line added: the word is where it was, so the fix still
        // applies, marked for review.
        let grown = ["運命の人", "新しい行"]
        let lines = await engine.romanize(lyrics: grown, songID: song)
        #expect(lines[0].text == "sadame no hito")
        #expect(lines[0].tokens[0].needsReview)
        let overrides = await store.overrides(for: song, lyricsHash: LyricsHash.make(grown))
        #expect(overrides.stale.count == 1)

        // The word itself gone from that place: kept in the store, not applied.
        let moved = ["あの運命の人"]
        let after = await engine.romanize(lyrics: moved, songID: song)
        #expect(after[0].text == "ano unmei no hito")
        #expect(await store.overrides(for: song, lyricsHash: LyricsHash.make(moved)).overrides.count == 1)

        // Looked at and kept: no longer stale.
        await store.confirm(overrides.overrides[0], lyricsHash: LyricsHash.make(grown), for: song)
        #expect(await store.overrides(for: song, lyricsHash: LyricsHash.make(grown)).stale.isEmpty)
    }

    @Test func aFixOverSeveralTokens() async {
        let store = OverrideStore(fileURL: nil)
        let engine = RomajiEngine(analyzer: TestSupport.engine.analyzer, store: store)
        let lyrics = ["花火大会の夜"]
        await store.set(
            ReadingOverride(line: 0, range: 0..<4, surface: "花火大会", reading: "まつり", lyricsHash: LyricsHash.make(lyrics)), for: song)
        let lines = await engine.romanize(lyrics: lyrics, songID: song)
        #expect(lines[0].text == "matsuri no yoru")
    }

    @Test func savedAndReadBack() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("romaji-overrides-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let first = OverrideStore(fileURL: url)
        await first.set(ReadingOverride(line: 2, range: 1..<3, surface: "未来", reading: "あした", lyricsHash: "h"), for: song)
        let second = OverrideStore(fileURL: url)
        let read = await second.overrides(for: song, lyricsHash: "h")
        #expect(read.overrides.map(\.reading) == ["あした"])
        #expect(read.version == 1)
        await second.remove(line: 2, range: 1..<3, for: song)
        #expect(await OverrideStore(fileURL: url).overrides(for: song, lyricsHash: "h").overrides.isEmpty)
    }
}

@Suite struct KaraokeMarksTests {
    @Test func marksCarryWordTimingsToTheRomaji() {
        let line = TestSupport.engine.romanize(line: "君の声")  // kimi no koe
        let marks = line.marks()
        #expect(marks == [0, 4, 7, 11])
        // Monotonic, from nothing to the whole line.
        let longer = TestSupport.engine.romanize(line: "100回目のキス、Love を 叫べ！")
        let m = longer.marks()
        #expect(m.count == longer.displayText.count + 1)
        #expect(m.first == 0 && m.last == Double(longer.text.count))
        #expect(zip(m, m.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func marksFollowTheLineAsWritten() {
        let source = "運命(さだめ)の人"
        let line = TestSupport.engine.romanize(line: source)  // sadame no hito
        let marks = line.marks(sourceCount: source.count)
        #expect(marks.count == source.count + 1)
        #expect(marks[0] == 0)
        #expect(marks[2] == 6)  // after 運命
        #expect(marks[7] == 6)  // through the markup, still there
        #expect(marks.last == 14)
    }

    @Test func noticesAreInTheBundle() {
        #expect(ThirdPartyNotices.text.contains("Nara Institute of Science and Technology"))
        #expect(ThirdPartyNotices.text.contains("NO WARRANTY"))
        #expect(ThirdPartyNotices.text.contains("Taku Kudo"))
    }
}
