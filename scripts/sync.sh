#!/usr/bin/env bash
# Re-fetch one borrowed source from upstream at the ref pinned in skills/borrowed/SOURCES.yaml.
# Usage: scripts/sync.sh SOURCE [REF]   (REF bumps the pin first; branch names resolve to a SHA)
# Other sources are left alone.
set -euo pipefail
cd "$(dirname "$0")/.."
sources=skills/borrowed/SOURCES.yaml

source=${1:-}
[ -n "$source" ] || {
  echo "usage: make sync SOURCE=<name> [REF=<sha|branch>]" >&2
  echo "sources: $(awk -f scripts/sources.awk "$sources" | awk '{print $1}' | sort -u | tr '\n' ' ')" >&2
  exit 1
}

fields=$(awk -f scripts/sources.awk "$sources" | awk -v s="$source" '$1 == s')
[ -n "$fields" ] || { echo "unknown source: $source" >&2; exit 1; }

repo=$(awk '$2 == "repo" {print $3}' <<<"$fields")
ref=${2:-$(awk '$2 == "ref" {print $3}' <<<"$fields")}
[ -n "$repo" ] && [ -n "$ref" ] || { echo "source $source needs a repo and ref" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

git -C "$tmp" init -q
git -C "$tmp" remote add origin "$repo"
git -C "$tmp" fetch -q --depth 1 origin "$ref"
sha=$(git -C "$tmp" rev-parse FETCH_HEAD)
git -C "$tmp" checkout -q FETCH_HEAD

# Check every path exists before touching the pool, so a bad manifest leaves it intact.
skills=$(awk '$2 == "skill" {print $3, $4}' <<<"$fields")
while read -r name path; do
  [ -d "$tmp/$path" ] || { echo "missing upstream path: $path" >&2; exit 1; }
done <<<"$skills"

dest=skills/borrowed/$source
rm -rf "$dest"
mkdir -p "$dest"
while read -r name path; do
  cp -R "$tmp/$path" "$dest/$name"
  echo "synced $source/$name"
done <<<"$skills"

# Rewrite only this source's ref line.
awk -v s="$source" -v sha="$sha" '
  /^  [^ ]/ { cur = $1; sub(":$", "", cur) }
  cur == s && /^    ref:/ { print "    ref: " sha; next }
  { print }
' "$sources" >"$tmp/SOURCES.yaml"
cp "$tmp/SOURCES.yaml" "$sources"
echo "pinned $source $repo@$sha"
