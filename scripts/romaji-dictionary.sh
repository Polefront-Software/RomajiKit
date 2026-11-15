#!/bin/sh
# Builds what an app fetches to read Japanese: IPAdic with only the
# fields RomajiKit reads, its licence, the exception list and the gikun
# hints, as one archive with a manifest beside it.
#
# usage: scripts/romaji-dictionary.sh [--full]
#   --full   keep every field of IPAdic (to compare against)
#
# Out comes .build/romaji-pack/site: manifest.json and the archive it
# names. Put both where the app's PackStore source points; this
# repository attaches them to each release. The
# version is a hash of the contents, so a change to any entry, to the
# exception list or to the hints makes a new version, and the app takes
# it the next time it looks.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
kit="$root"
work="$kit/.build/romaji-pack"
variant=trimmed
if [ "${1:-}" = "--full" ]; then variant=full; fi

source="$kit/.build/checkouts/Mecab-Swift/Sources/mecab"
[ -d "$source/mecab-ipadic" ] || (cd "$kit" && swift package resolve)

# MeCab's own dictionary compiler, built once from the same source.
tool="$work/tool/src/mecab-dict-index"
if [ ! -x "$tool" ]; then
    rm -rf "$work/tool"
    mkdir -p "$work"
    cp -R "$source/mecab" "$work/tool"
    (cd "$work/tool" && ./configure --with-charset=utf8 >/dev/null && make -j8 >/dev/null 2>&1)
fi

entries="$work/$variant-source"
pack="$work/$variant"
rm -rf "$entries" "$pack"
mkdir -p "$pack"
flag=
[ "$variant" = full ] && flag=--full
python3 -I "$kit/Tools/trim_ipadic.py" $flag "$source/mecab-ipadic" "$entries"
# The compiler reads its settings from the tool's own folder.
"$tool" -d "$entries" -o "$pack" -f EUC-JP -t UTF-8 >/dev/null
# IPAdic's terms go with every copy of it.
cp "$entries/dicrc" "$source/mecab-ipadic/COPYING" "$pack/"
cp "$kit/Sources/RomajiKit/Resources/exceptions.json" "$kit/Sources/RomajiKit/Resources/gikun-hints.json" "$pack/"

version=$(cd "$pack" && find . -type f | LC_ALL=C sort | xargs shasum -a 256 | shasum -a 256 | cut -c1-16)
site="$work/site"
[ "$variant" = full ] && site="$work/site-full"
rm -rf "$site"
mkdir -p "$site"
archive="romaji-pack-$version.aar"
aa archive -d "$pack" -o "$site/$archive" -a lzfse
size=$(stat -f %z "$site/$archive")
sum=$(shasum -a 256 "$site/$archive" | cut -d' ' -f1)
cat > "$site/manifest.json" <<JSON
{"version": "$version", "archive": "$archive", "size": $size, "sha256": "$sum"}
JSON

echo "pack     $pack ($(du -sk "$pack" | cut -f1) KB on disk)"
echo "archive  $site/$archive ($((size / 1024)) KB)"
echo "version  $version"
