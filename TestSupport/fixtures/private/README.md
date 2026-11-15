# Private real-song fixtures (never commit)

Put real songs from your own library here to measure accuracy on actual lyrics.
This folder is git-ignored: song lyrics are copyrighted, so they stay local.

Use the same format as `../reading_cases.json`, in a file named `songs.json`:

```json
{"schema": "romaji-readings-v1", "cases": [
  {"id": "S001-03", "category": "gikun_ruby", "text": "<one lyric line>",
   "expected": "<full reading in hiragana>",
   "ruby": [{"surface": "<kanji>", "reading": "<sung reading>"}],
   "focus": [{"surface": "<kanji>", "reading": "<reading>"}],
   "note": "<song title> line 3, readings from the official booklet"}
]}
```

Where to get correct readings: the CD booklet / official lyric site furigana,
or have a native speaker check. Aim for 20–30 songs and at least 300 lines.
Score it with: `python3 -I tools/score_readings.py results.json --gold fixtures/private/songs.json`
