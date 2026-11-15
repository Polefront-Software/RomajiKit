"""Score an engine's reading output against fixtures/reading_cases.json.

The app's test target (or a debug export) writes a results JSON:

{
  "engine": "mecab-ipadic+exceptions",          # free text, shown in the report
  "cases": [
    {"id": "H12",
     "reading": "ひとけのないこうえん",            # whole line, hiragana or katakana
     "spans": [{"surface": "人気", "reading": "ひとけ", "source": "classifier",
                "needs_review": false}, ...]}
  ]
}

usage: python3 -I tools/score_readings.py results.json [--gold FILE] [--min-line 0.85]
            [--min-focus 0.90] [--json report.json]

Gates (exit code 1 if any fails):
  * gikun_ruby: 100% line-exact (ruby must always win)
  * gikun_unmarked: the gikun word must carry needs_review = true
  * all other categories together: line-exact >= --min-line, focus >= --min-focus
"""
import argparse, json, os, re, sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def norm(s):
    s = "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in s)
    return re.sub(r"[\s、。，．,.!?！？「」『』…・〜~]", "", s).lower()


def edit_distance(a, b):
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def focus_hit(spans, f):
    ok = {norm(f["reading"])} | {norm(a) for a in f.get("alternatives", [])}
    for s in spans:
        if s["surface"] == f["surface"]:
            return norm(s["reading"]) in ok, s
    for s in spans:  # analyzer split differently: accept a containing span
        if f["surface"] in s["surface"]:
            return any(o in norm(s["reading"]) for o in ok), s
    return False, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("results")
    ap.add_argument("--min-line", type=float, default=0.85)
    ap.add_argument("--min-focus", type=float, default=0.90)
    ap.add_argument("--json")
    ap.add_argument("--gold", default=os.path.join(ROOT, "fixtures", "reading_cases.json"),
                    help="gold set (default: public fixtures; use fixtures/private/songs.json for real songs)")
    a = ap.parse_args()

    gold = {c["id"]: c for c in json.load(open(a.gold, encoding="utf-8"))["cases"]}
    res = json.load(open(a.results, encoding="utf-8"))
    got = {c["id"]: c for c in res["cases"]}

    per = defaultdict(lambda: dict(n=0, exact=0, chars=0, errs=0, fn=0, fok=0))
    misses, review_ok, gates = [], True, []
    for cid, g in gold.items():
        cat, st = g["category"], per[g["category"]]
        r = got.get(cid)
        st["n"] += 1
        targets = [norm(g["expected"])] + [norm(x) for x in g.get("alternatives", [])]
        if r is None:
            misses.append((cid, cat, "MISSING", g["expected"], ""))
            st["chars"] += len(targets[0]); st["errs"] += len(targets[0])
            continue
        hyp = norm(r["reading"])
        d = min(edit_distance(hyp, t) for t in targets)
        st["chars"] += len(targets[0]); st["errs"] += d
        if d == 0:
            st["exact"] += 1
        else:
            misses.append((cid, cat, "line", g["expected"], r["reading"]))
        for f in g.get("focus", []):
            st["fn"] += 1
            hit, span = focus_hit(r.get("spans", []), f)
            st["fok"] += hit
            if cat == "gikun_unmarked":
                if not (span and span.get("needs_review")):
                    review_ok = False
                    misses.append((cid, cat, "no review flag", f["surface"], span and span["reading"]))
            elif not hit:
                misses.append((cid, cat, f"focus {f['surface']}", f["reading"], span and span["reading"]))

    print(f"Engine: {res.get('engine', '?')}\n")
    print(f"{'category':16} {'lines':>5} {'exact':>7} {'CER':>6} {'focus':>7}")
    tot = dict(n=0, exact=0, chars=0, errs=0, fn=0, fok=0)
    for cat in sorted(per):
        s = per[cat]
        if cat not in ("gikun_ruby", "gikun_unmarked"):
            for k in tot: tot[k] += s[k]
        fr = f"{s['fok']}/{s['fn']}" if s["fn"] else "-"
        print(f"{cat:16} {s['n']:>5} {s['exact'] / s['n']:>7.0%} {s['errs'] / max(1, s['chars']):>6.1%} {fr:>7}")
    line_rate = tot["exact"] / max(1, tot["n"])
    focus_rate = tot["fok"] / max(1, tot["fn"])
    print(f"{'OVERALL*':16} {tot['n']:>5} {line_rate:>7.0%} {tot['errs'] / max(1, tot['chars']):>6.1%} "
          f"{focus_rate:>7.0%}\n  *excluding gikun categories (gated separately)\n")

    gr = per["gikun_ruby"]
    gates.append(("ruby always wins (gikun_ruby 100%)", gr["exact"] == gr["n"]))
    gates.append(("unmarked gikun flagged for review", review_ok))
    gates.append((f"line-exact >= {a.min_line:.0%}", line_rate >= a.min_line))
    gates.append((f"focus >= {a.min_focus:.0%}", focus_rate >= a.min_focus))
    for name, ok in gates:
        print(f"[{'PASS' if ok else 'FAIL'}] {name}")
    if misses:
        print("\nMisses:")
        for m in misses:
            print(f"  {m[0]:4} {m[1]:15} {m[2]:16} expected {m[3]}  got {m[4]}")
    if a.json:
        json.dump(dict(engine=res.get("engine"), line_exact=line_rate, focus=focus_rate,
                       per_category=per, gates=gates, misses=misses),
                  open(a.json, "w"), ensure_ascii=False, indent=1)
    sys.exit(0 if all(ok for _, ok in gates) else 1)


if __name__ == "__main__":
    main()
