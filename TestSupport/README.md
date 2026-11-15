# Romaji test kit

Test system for RomajiKit, on-device Japanese → romaji for lyrics. Contents:

| Path | What it is |
|---|---|
| `reference/romaji.py` | Reference implementation of the reading resolver and kana→romaji renderer. The Swift code ports it line for line. |
| `fixtures/renderer_cases.json` | 19 hand-checked token lines × 4 presets = 76 exact-match tests (the kit's 16 lines, plus R17 to R19 added while porting). Must pass at 100%. |
| `fixtures/reading_cases.json` | 46 original lyric lines in 8 categories, each with its correct reading. Measures how accurate the analyzer pipeline is. |
| `fixtures/private/` | Your real songs, git-ignored (lyrics are copyrighted). See its README. |
| `tools/check_reference.py` | Runs the reference against the renderer fixtures. |
| `tools/fuzz_reference.py` | Random kana in every preset must never leave Japanese characters in the output. |
| `tools/score_readings.py` | Scores the app's reading output and applies the gates below. |
| `PROMPT.md` | Build prompt to paste into Claude Code. |

## Run

```sh
python3 -I tools/check_reference.py      # 76/76 passed
python3 -I tools/fuzz_reference.py       # 0 leaks
python3 -I tools/score_readings.py results.json   # results.json comes from the Swift test run
```

Needs only Python 3.9 or newer, with no packages.

## Gates in `score_readings.py`

- **Ruby always wins:** gikun lines that have furigana must be 100% correct.
- **Unmarked gikun is flagged:** a word whose sung reading isn't written anywhere must carry `needs_review`.
- **Whole lines:** at least 85% of the remaining lines exactly right (`--min-line`).
- **Focus words:** at least 90% of the focus words right (`--min-focus`).

Raise the thresholds once the first baseline is measured.

## Renderer conventions (presets)

| | singalong (default) | learner | official (2025 notice) | kunrei |
|---|---|---|---|---|
| Long vowels | as written: ou, oo, aa | macron ō | as written | circumflex ô |
| っち | tch | tch | cch | tt (tti) |
| ん + vowel/y | n' | n' | n' | n' |
| は/へ/を as particles | wa / e / o | wa / e / o | wa / e / o | wa / e / o |

Rules for all presets:
- A word-final ん never takes an apostrophe because of the next word.
- A word-final っ looks ahead only into an attached ending (待っ+て → matte).
- In verbs and adjectives, a final う or い is never treated as a long vowel (思う → omou).
- ei and ii never become long vowels.

## Bugs found while building this (keep them out of the Swift port)

1. ん took an apostrophe from the next separate word ("shunkan' e").
2. っ at the end of a token was dropped before an attached ending ("fute" instead of "futte").
3. Checking an empty string with `in` returns true, so "no next sound" was treated as a vowel.
4. っ before punctuation doubled the comma ("a,, vu").
5. Small kana ゎ ヵ ヶ and ヷ–ヺ were missing from the table (found by the fuzz test).
6. Latin words lost their vowels to long-vowel merging in the macron presets ("soon" became "sōn"). A token with no kana now passes through whole (R17).
7. 『』（）【】〜 and full-width , . : ; were left as they were; they are mapped now (R18).
8. The volitional ending (行こ + う, as a dictionary cuts it) was never a long vowel in the macron presets: "ikou" beside "kyō". It is one ō with the stem's o now (R19).

## How it is run

The Swift package reads these fixtures in its tests (`swift test`);
`scripts/romaji-eval.sh` runs everything.
