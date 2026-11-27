#!/usr/bin/env bash
# Builds release/AntiGrief-<version>.zip from a commit (default HEAD).
# The zip holds one folder, AntiGrief/, with the TOC, every file the TOC
# loads, the media it uses, and LICENSE/README/CHANGELOG. Uncommitted changes
# are never included: the files come from git, not from the working tree.
#
#   scripts/package.sh            # package HEAD
#   scripts/package.sh v1.0.0     # package a tag or commit
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
REF="${1:-HEAD}"
git rev-parse --verify --quiet "$REF^{commit}" >/dev/null || { echo "unknown ref: $REF" >&2; exit 1; }

TOC="$(git show "$REF:AntiGrief.toc" | tr -d '\r')"
VERSION="$(printf '%s\n' "$TOC" | sed -n 's/^## Version:[[:space:]]*//p' | head -1)"
[ -n "$VERSION" ] || { echo "no '## Version:' line in AntiGrief.toc" >&2; exit 1; }

# Files the TOC loads: every line that isn't blank or a ## / # comment
mapfile -t LOADED < <(printf '%s\n' "$TOC" | sed -e 's/[[:space:]]*$//' | grep -v -e '^#' -e '^$')
FILES=(AntiGrief.toc "${LOADED[@]}" media/minimap.tga LICENSE README.md CHANGELOG.md)

for f in "${FILES[@]}"; do
  git cat-file -e "$REF:$f" 2>/dev/null || { echo "missing in $REF: $f" >&2; exit 1; }
done

if [ "$REF" = "HEAD" ] && [ -n "$(git status --porcelain -- "${FILES[@]}")" ]; then
  echo "warning: uncommitted changes to packaged files are NOT included" >&2
fi

mkdir -p release
OUT="release/AntiGrief-$VERSION.zip"
git archive --format=zip --prefix=AntiGrief/ -o "$OUT" "$REF" -- "${FILES[@]}"
echo "$OUT"
