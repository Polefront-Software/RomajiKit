"""Run the Python reference renderer against fixtures/renderer_cases.json.
Must report 0 failures. The Swift port must match the same fixture 1:1.

usage: python3 -I tools/check_reference.py
"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "reference"))
from romaji import render_line  # noqa: E402


def main():
    data = json.load(open(os.path.join(ROOT, "fixtures", "renderer_cases.json"), encoding="utf-8"))
    fails = total = 0
    for c in data["cases"]:
        ov = {}
        for o in c.get("overrides", []):
            ov.setdefault((0, o["token"]), []).append(o)
        for preset, exp in c["expected"].items():
            total += 1
            got, _ = render_line(c["tokens"], preset, ov, 0)
            if got != exp:
                fails += 1
                print(f"FAIL {c['id']} [{preset}]\n  got:      {got}\n  expected: {exp}\n  note:     {c['note']}")
    print(f"{total - fails}/{total} passed")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
