#!/usr/bin/env bash
# Re-fetch borrowed skills from upstream at the ref pinned in borrowed/SOURCES.yaml.
# Usage: scripts/sync.sh [REF]   (REF bumps the pin first; branch names resolve to a SHA)
set -euo pipefail
cd "$(dirname "$0")/.."
sources=borrowed/SOURCES.yaml

repo=$(awk '/^repo:/ {print $2}' "$sources")
ref=${1:-$(awk '/^ref:/ {print $2}' "$sources")}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

git -C "$tmp" init -q
git -C "$tmp" remote add origin "$repo"
git -C "$tmp" fetch -q --depth 1 origin "$ref"
sha=$(git -C "$tmp" rev-parse FETCH_HEAD)
git -C "$tmp" checkout -q FETCH_HEAD

awk '/^skills:/ {in_skills=1; next} in_skills && /^  [^ ]/ {sub(":", "", $1); print $1, $2}' "$sources" |
while read -r name path; do
  [ -d "$tmp/$path" ] || { echo "missing upstream path: $path" >&2; exit 1; }
  rm -rf "borrowed/$name"
  cp -R "$tmp/$path" "borrowed/$name"
  echo "synced $name"
done

sed -i '' "s/^ref: .*/ref: $sha/" "$sources"
echo "pinned $repo@$sha"
