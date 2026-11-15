"""Fuzz: random kana in every preset must never leave Japanese characters
or crash. The Swift port should run the same check (fixed seed).
usage: python3 -I tools/fuzz_reference.py [iterations]"""
import os, random, re, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "reference"))
from romaji import render_token, PRESETS  # noqa: E402

N = int(sys.argv[1]) if len(sys.argv) > 1 else 20000
rng = random.Random(42)
kana = [chr(c) for c in range(0x3041, 0x3097)] + [chr(c) for c in range(0x30A1, 0x30FB)] + ["ー"]
bad = 0
for preset in PRESETS:
    for _ in range(N):
        s = "".join(rng.choice(kana) for _ in range(rng.randint(1, 6)))
        for pos in ("noun", "verb", "particle"):
            out = render_token(s, pos, PRESETS[preset])
            if re.search(r"[぀-ヿ]", out):
                bad += 1
                if bad <= 10: print("LEAK", preset, pos, s, "->", out)
print(f"{bad} leaks in {N * 3 * len(PRESETS)} renders")
sys.exit(1 if bad else 0)
