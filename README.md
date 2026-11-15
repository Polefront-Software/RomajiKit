# RomajiKit

Japanese lyrics to romaji, on the device. A Swift package with no UI, for iOS, macOS,
watchOS and tvOS.

Lyrics are hard to romanise because of readings, not spelling: a song writes 運命 and sings
さだめ. RomajiKit reads each line with MeCab and the IPA dictionary, marks the words that
may be sung another way than they are written, lets furigana written in the lyrics win,
and keeps a listener's own fixes per song.

```swift
import RomajiKit

// The dictionary is fetched once and kept up to date.
let packs = PackStore(
    folder: applicationSupport.appending(path: "Romaji/Dictionary"),
    source: URL(string: "https://github.com/Polefront-Software/RomajiKit/releases/latest/download"))
_ = try await packs.refresh()

if let pack = await packs.installed {
    let engine = try RomajiEngine(pack: pack)
    let line = engine.romanize(line: "未来(あした)へ歩き出そう", preset: .learner)
    print(line.text)                             // ashita e arukidasō
    for word in line.tokens where word.needsReview { print(word.surface) }
}
```

## What it does

- **Readings**: MeCab with IPAdic, behind a `JapaneseAnalyzer` protocol; the system
  tokenizer stands in for words the dictionary lacks.
- **Numbers** with their counters: 100回 is hyakkai, 一人 is hitori.
- **Known dictionary errors** corrected by a list (`exceptions.json`), and words often sung
  another way marked for review (`gikun-hints.json`).
- **Furigana in the lyrics** always wins, in four spellings: `運命(さだめ)`, `運命（さだめ）`,
  `|運命《さだめ》`, `{運命|さだめ}`.
- **A place for your own picker** (`ReadingDisambiguator`): asked once per line for readings
  that depend on the words around a word, taken over the dictionary and under furigana and
  fixes. The package ships none.
- **Fixes per song** (`OverrideStore`), kept on the device and marked stale when the lyrics
  change.
- **Four spellings** (`RomajiPreset`): sing-along (toukyou), learner (tōkyō), official 2025,
  Kunrei.
- **Word timing**: each word keeps its place in the line as written, so romaji can be
  highlighted in time with the original.

## The dictionary pack

The dictionary is not inside the package. `scripts/romaji-dictionary.sh` builds a pack:
IPAdic with every word and only the fields RomajiKit reads, its licence, and the two lists
above; about 11 MB to fetch and 39 MB on the device. Each release of this repository
carries the pack and its `manifest.json`.

`PackStore` fetches the pack the first time, looks once a day for a newer one, checks it
against the manifest's hash and puts it in place whole or not at all. The pack's version
is a hash of its contents, so a change to any word or list is a new version.

## Checking it

```sh
scripts/romaji-eval.sh          # reference checks, pack, Swift tests, scorer table
scripts/romaji-eval.sh --fast   # without building the pack or the scorer
```

`TestSupport/` holds the reference renderer in Python, the fixtures and the scorer; its
README has the renderer's conventions. The fixture is the spec: a change to how romaji is
written goes into `reference/romaji.py` and the fixture first, then into Swift. The lines
in the fixtures are written for the purpose; real lyrics are copyrighted and stay out of
this repository (`TestSupport/fixtures/private/` is ignored).

Current score on the reading fixture: 97% of lines exact, character error rate 0.8%.

## Licence

RomajiKit is under the MIT licence (`LICENSE`). MeCab, IPAdic and Mecab-Swift have their
own terms; see `NOTICE.md`. An app that uses the package must show the text in
`Sources/RomajiKit/Resources/ThirdPartyNotices.txt` (`ThirdPartyNotices.text`).
