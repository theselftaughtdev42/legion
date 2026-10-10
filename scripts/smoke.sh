#!/usr/bin/env bash
# Spin up a throwaway sandbox for one agent on a scratch repo and check its kit landed as designed.
# Usage: scripts/smoke.sh <persona>-<role>
# Agent-specific checks live in agents/<agent>/smoke-checks.sh, sourced after the shared ones.
set -uo pipefail
cd "$(dirname "$0")/.."

agent=${1:?usage: scripts/smoke.sh <persona>-<role>}
kit=agents/$agent
[ -f "$kit/spec.yaml" ] || { echo "no agent at $kit/"; exit 1; }

name=${agent%%-*}-smoke-$$
repo=$(mktemp -d "${TMPDIR%/}/$name.XXXXXX")
git -C "$repo" init -q && git -C "$repo" commit -q --allow-empty -m init

cleanup() { sbx rm -f "$name" >/dev/null 2>&1 || sbx rm "$name" >/dev/null 2>&1; rm -rf "$repo"; }
trap cleanup EXIT

sbx create --skills=off --name "$name" claude --kit "./$kit" --kit ./no-attribution "$repo" >/dev/null || exit 1
sbx run -d --name "$name" >/dev/null 2>&1 || true   # make sure startup commands have run

fails=0
result() {  # result <0 for pass> <description>
  if [ "$1" = 0 ]; then echo "ok   $2"; else echo "FAIL $2"; fails=$((fails+1)); fi
}
check() {  # check <description> <shell snippet run in sandbox>
  sbx exec "$name" bash -c "$2" >/dev/null 2>&1
  result $? "$1"
}

for s in $(awk -f scripts/sources.awk skills/borrowed/SOURCES.yaml | awk '$2 == "skill" {print $3}'); do
  check "skill $s present" "test -f ~/.claude/skills/$s/SKILL.md"
done
check "shared store hidden (no extra skills)" "[ \$(ls ~/.claude/skills | wc -l) -eq $(ls "$kit/files/home/.claude/skills" | wc -l) ]"
check "attribution disabled" "jq -e '.attribution == {\"commit\": \"\", \"pr\": \"\"}' ~/.claude/settings.json"
check "sbx claude settings preserved" "jq -e '.permissions.defaultMode' ~/.claude/settings.json"
check "workspace is a writable bind mount" "test -w '$repo'"
check "gh authenticated" "gh auth status"

# Agent-specific checks: may use check, result, $name and $repo.
if [ -f "$kit/smoke-checks.sh" ]; then
  # shellcheck source=/dev/null
  . "$kit/smoke-checks.sh"
fi

echo; [ "$fails" -eq 0 ] && echo "smoke: all checks passed" || { echo "smoke: $fails check(s) failed"; exit 1; }
