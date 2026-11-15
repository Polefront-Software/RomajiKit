#!/usr/bin/env python3
"""Copies IPAdic's source with only the fields RomajiKit reads.

usage: trim_ipadic.py [--full] <mecab-ipadic source> <output folder>
  --full   keep every field (to compare against)

Every word stays, with its costs and context ids, so MeCab cuts a line
exactly as it does with the full dictionary. What goes is text the
package never looks at. The rules follow IPAdicMapping.swift field by
field; change them together.

  0, 1  part of speech and its first detail   kept
  2, 3  finer detail                          dropped
  4     conjugation type                      kept for 助動詞 (the copula)
  5     conjugation form                      dropped
  6     base form                             kept for 動詞 非自立 (いる after て)
  7     reading                               kept
  8     pronunciation                         kept where it differs from the reading

The entries go into one file, the source's files in the order of their
names. Where two words are spelled alike and cost the same, MeCab takes
the one it met first, and it meets files in whatever order the disk
lists them; one file makes that order the same on every machine.
"""
import glob
import os
import shutil
import sys

FIRST = 4  # surface, left id, right id, cost come before the features


def trim(columns):
    if len(columns) < FIRST + 9:
        return columns
    f = columns[FIRST:]
    f[2] = f[3] = f[5] = "*"
    if f[0] != "助動詞":
        f[4] = "*"
    if not (f[0] == "動詞" and f[1] == "非自立"):
        f[6] = "*"
    if f[8] == f[7]:
        f[8] = "*"
    return columns[:FIRST] + f


def main(source, output, full=False):
    os.makedirs(output, exist_ok=True)
    for path in glob.glob(os.path.join(source, "*.def")) + [os.path.join(source, "dicrc")]:
        shutil.copy(path, output)
    entries = 0
    with open(os.path.join(output, "ipadic.csv"), "w", encoding="euc_jp") as out:
        for path in sorted(glob.glob(os.path.join(source, "*.csv"))):
            with open(path, encoding="euc_jp") as lines:
                for line in lines:
                    columns = line.rstrip("\n").split(",")
                    out.write(",".join(columns if full else trim(columns)) + "\n")
                    entries += 1
    print(f"{entries} entries")


if __name__ == "__main__":
    arguments = [a for a in sys.argv[1:] if a != "--full"]
    if len(arguments) != 2:
        sys.exit(__doc__)
    main(arguments[0], arguments[1], full="--full" in sys.argv)
