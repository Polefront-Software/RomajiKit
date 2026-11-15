"""Reference prototype of the on-device lyrics pipeline's own parts:
1. reading resolution (per-song overrides with a source priority)
2. deterministic kana -> romaji renderer with style presets.

Analyzer output (MeCab/UniDic tokens) is supplied as data here, since no
analyzer is installed in the test workspace. Port to Swift 1:1.
"""

# ---------- 1. Reading resolution ----------

# Higher number wins.
SOURCE_PRIORITY = {
    "dictionary": 1,      # MeCab / UniDic default reading
    "exception": 2,       # app-wide exception list (known dictionary errors)
    "classifier": 3,      # heteronym classifier / Foundation Models pick
    "audio": 4,           # SpeechTranscriber mismatch suggestion
    "ruby": 5,            # furigana from official / pasted lyrics
    "user": 6,            # user's own fix in the editor
}


def resolve(token, song_overrides, line_no, idx):
    """Pick the reading for one token. Overrides are keyed per song + position,
    never globally, because the same kanji is sung differently per song."""
    best = (token["reading"], "dictionary")
    for ov in song_overrides.get((line_no, idx), []):
        if SOURCE_PRIORITY[ov["source"]] > SOURCE_PRIORITY[best[1]]:
            best = (ov["reading"], ov["source"])
    return best


# ---------- 2. Kana -> romaji ----------

def kata_to_hira(s):
    return "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in s)


BASE = {
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
}
# Two-kana combinations (yōon + loanword sounds)
COMBO = {}
for k, c in {"き": "k", "ぎ": "g", "に": "n", "ひ": "h", "び": "b", "ぴ": "p",
             "み": "m", "り": "r"}.items():
    COMBO[k + "ゃ"], COMBO[k + "ゅ"], COMBO[k + "ょ"] = c + "ya", c + "yu", c + "yo"
for k, c in {"し": "sh", "ち": "ch", "じ": "j", "ぢ": "j"}.items():
    COMBO[k + "ゃ"], COMBO[k + "ゅ"], COMBO[k + "ょ"] = c + "a", c + "u", c + "o"
    COMBO[k + "ぇ"] = c + "e"
COMBO.update({
    "てぃ": "ti", "でぃ": "di", "とぅ": "tu", "どぅ": "du", "てゅ": "tyu", "でゅ": "dyu",
    "ふぁ": "fa", "ふぃ": "fi", "ふぇ": "fe", "ふぉ": "fo", "ふゅ": "fyu",
    "ゔぁ": "va", "ゔぃ": "vi", "ゔぇ": "ve", "ゔぉ": "vo",
    "うぃ": "wi", "うぇ": "we", "うぉ": "wo", "つぁ": "tsa", "つぃ": "tsi",
    "つぇ": "tse", "つぉ": "tso", "いぇ": "ye", "くぁ": "kwa", "くゎ": "kwa", "ぐぁ": "gwa",
})

PUNCT = {"、": ",", "。": ".", "「": "\"", "」": "\"", "！": "!", "？": "?", "　": " ", "…": "...",
         "『": "\"", "』": "\"", "（": "(", "）": ")", "【": "[", "】": "]", "〜": "~", "～": "~",
         "，": ",", "．": ".", "：": ":", "；": ";"}

KUNREI = {"shi": "si", "chi": "ti", "tsu": "tu", "fu": "hu", "ji": "zi",
          "sha": "sya", "shu": "syu", "sho": "syo", "cha": "tya", "chu": "tyu",
          "cho": "tyo", "ja": "zya", "ju": "zyu", "jo": "zyo"}

PRESETS = {
    # long: "kana" = spell as written (ou, oo, ei); "macron"; "circumflex"
    "singalong": dict(long="kana", sokuon_ch="tch", kunrei=False, wo="o"),
    "learner":   dict(long="macron", sokuon_ch="tch", kunrei=False, wo="o"),
    "official":  dict(long="kana", sokuon_ch="cch", kunrei=False, wo="o"),
    "kunrei":    dict(long="circumflex", sokuon_ch="tt", kunrei=True, wo="o"),
}

VOWELS = "aeiou"
MACRON = {"a": "ā", "i": "ī", "u": "ū", "e": "ē", "o": "ō"}
CIRC = {"a": "â", "i": "î", "u": "û", "e": "ê", "o": "ô"}


def kana_units(h):
    """Split hiragana into syllable units (longest match)."""
    out, i = [], 0
    while i < len(h):
        if h[i:i + 2] in COMBO:
            out.append(h[i:i + 2]); i += 2
        else:
            out.append(h[i]); i += 1
    return out


def unit_romaji(u, p):
    r = COMBO.get(u) or BASE.get(u)
    if r is None:
        return PUNCT.get(u, u)  # unknown char (latin, punctuation) passes through
    if p["kunrei"]:
        r = KUNREI.get(r, r)
    return r


def has_kana(h):
    return any("ぁ" <= c <= "ヿ" for c in h)


def render_token(reading, pos, p, next_head=""):
    h = kata_to_hira(reading)
    # a token with no kana (Latin words, digits, punctuation) passes through:
    # its vowels are never merged into long vowels ("soon" stays "soon")
    if not has_kana(h):
        return "".join(PUNCT.get(c, c) for c in h)
    # particles by grammatical role, not by kana
    if pos == "particle":
        if h == "は": return "wa"
        if h == "へ": return "e"
        if h == "を": return p["wo"]
    units = kana_units(h)
    syl = []  # list of romaji syllables, with markers
    for u in units:
        if u == "っ":
            syl.append("<Q>")
        elif u == "ん":
            syl.append("<N>")
        elif u == "ー":
            syl.append("<L>")
        else:
            syl.append(unit_romaji(u, p))
    # verb/adjective endings: final う / い are not long-vowel extensions
    protect_last = pos in ("verb", "adj") and len(syl) >= 2
    out = []
    for i, s in enumerate(syl):
        nxt = syl[i + 1] if i + 1 < len(syl) else next_head
        prev = out[-1] if out else ""
        if s == "<Q>":
            if nxt.startswith("ch"):
                out.append("t" if p["sokuon_ch"] == "tch" else "c")
            elif nxt[:1].isascii() and nxt[:1].isalpha() and nxt[0].lower() not in VOWELS:
                out.append(nxt[0])
            else:
                out.append("")  # word-final っ (e.g. exclamation): drop
            continue
        if s == "<N>":
            out.append("n'" if nxt[:1] and nxt[0] in VOWELS + "y" else "n")
            continue
        if s == "<L>":
            v = prev[-1] if prev and prev[-1] in VOWELS else ""
            if p["long"] == "kana":
                out.append(v)
            elif v:
                table = MACRON if p["long"] == "macron" else CIRC
                out[-1] = prev[:-1] + table[v]
            continue
        # long vowels written with kana: oo/ou, uu, aa (not ei/ii)
        if p["long"] != "kana" and prev and s in ("u", "o", "a") and \
                not (protect_last and i == len(syl) - 1):
            v = prev[-1]
            if (v == "o" and s in ("o", "u")) or (v == "u" and s == "u") or \
                    (v == "a" and s == "a"):
                table = MACRON if p["long"] == "macron" else CIRC
                out[-1] = prev[:-1] + table[v]
                continue
        out.append(s)
    return "".join(out)


def render_line(tokens, preset, song_overrides=None, line_no=0):
    p = PRESETS[preset]
    song_overrides = song_overrides or {}
    resolved = [resolve(t, song_overrides, line_no, i) for i, t in enumerate(tokens)]
    # render right-to-left so a token-final っ can see the next token's sound
    rendered, next_head = [None] * len(tokens), ""
    for idx in range(len(tokens) - 1, -1, -1):
        rendered[idx] = render_token(resolved[idx][0], tokens[idx]["pos"], p, next_head)
        # っ/ん look across a boundary only into attached endings (待っ+て),
        # never into a separate word (瞬間 + へ must stay "shunkan e")
        next_head = rendered[idx] if tokens[idx].get("attach") else ""
    # volitional う on its stem (行こ + う) is one long ō with the stem's o:
    # ikō, omoō. Written out as "ou" where long vowels stay as written.
    if p["long"] != "kana":
        table = MACRON if p["long"] == "macron" else CIRC
        for idx in range(1, len(tokens)):
            t = tokens[idx]
            if t.get("attach") and t["pos"] == "aux" and kata_to_hira(resolved[idx][0]) == "う" \
                    and rendered[idx - 1].endswith("o"):
                rendered[idx - 1] = rendered[idx - 1][:-1] + table["o"]
                rendered[idx] = ""
    words = []
    for t, r in zip(tokens, rendered):
        if t.get("attach") and words:
            words[-1] += r
        else:
            words.append(r)
    return " ".join(words), [s for _, s in resolved]
