#!/bin/sh
# Publishes a version: checks everything, builds the dictionary pack,
# tags the commit and makes the release with the pack attached. Every
# release carries the pack, because apps fetch it from the latest one.
#
# usage: scripts/release.sh VERSION   (e.g. 0.2.0; needs gh, on main, pushed)
set -eu

version=${1:?usage: scripts/release.sh VERSION}
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
[ -z "$(git status --porcelain)" ] || { echo "Commit or set aside the changes first."; exit 1; }
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "Push main first."; exit 1; }

scripts/romaji-eval.sh
site="$root/.build/romaji-pack/site"
pack=$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' "$site/manifest.json")
gh release create "$version" "$site/manifest.json" "$site"/*.aar \
    --title "$version" --notes "Dictionary pack $pack."
