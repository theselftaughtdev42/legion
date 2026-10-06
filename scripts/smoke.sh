#!/usr/bin/env bash
# Spin up a throwaway Polly sandbox on a scratch repo and check the kit landed as designed.
set -uo pipefail
cd "$(dirname "$0")/.."

name=polly-smoke-$$
repo=$(mktemp -d "${TMPDIR%/}/polly-smoke.XXXXXX")
git -C "$repo" init -q && git -C "$repo" commit -q --allow-empty -m init

cleanup() { sbx rm -f "$name" >/dev/null 2>&1 || sbx rm "$name" >/dev/null 2>&1; rm -rf "$repo"; }
trap cleanup EXIT

sbx create --skills=off --name "$name" claude --kit ./polly-planner "$repo" >/dev/null || exit 1
sbx run -d --name "$name" >/dev/null 2>&1 || true   # make sure startup commands have run

fails=0
check() {  # check <description> <shell snippet run in sandbox>
  if sbx exec "$name" bash -c "$2" >/dev/null 2>&1; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails+1)); fi
}
guard() {  # guard <expected exit> <hook json>
  printf "%s" "$2" | sbx exec -i "$name" bash -c 'WORKSPACE_DIR='"$repo"' bash /home/agent/.polly/guard.sh' >/dev/null 2>&1
  local rc=$?
  if [ "$rc" = "$1" ]; then echo "ok   guard exit $1: $2"; else echo "FAIL guard exit $rc (want $1): $2"; fails=$((fails+1)); fi
}

for s in $(awk '/^skills:/ {s=1; next} s && /^  [^ ]/ {sub(":", "", $1); print $1}' borrowed/SOURCES.yaml); do
  check "skill $s present" "test -f ~/.claude/skills/$s/SKILL.md"
done
check "shared store hidden (no extra skills)" "[ \$(ls ~/.claude/skills | wc -l) -eq $(ls polly-planner/files/home/.claude/skills | wc -l) ]"
check "managed settings installed" "jq -e '.hooks.PreToolUse' /etc/claude-code/managed-settings.json"
check "Polly persona in managed memory" "grep -q 'You are \*\*Polly\*\*' /etc/claude-code/CLAUDE.md"
check "workspace is a writable bind mount" "test -w '$repo'"
check "gh authenticated" "gh auth status"

guard 0 '{"tool_name":"Write","tool_input":{"file_path":"GLOSSARY.md"}}'
guard 0 '{"tool_name":"Write","tool_input":{"file_path":"'"$repo"'/docs/adr/0001-x.md"}}'
guard 0 '{"tool_name":"Edit","tool_input":{"file_path":"src/billing/GLOSSARY.md"}}'
guard 2 '{"tool_name":"Edit","tool_input":{"file_path":"src/index.ts"}}'
guard 2 '{"tool_name":"Write","tool_input":{"file_path":"docs/adr/../../src/x.ts"}}'
guard 2 '{"tool_name":"Write","tool_input":{"file_path":"/etc/passwd"}}'
guard 2 '{"tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD"}}'
guard 2 '{"tool_name":"Bash","tool_input":{"command":"git stash"}}'
guard 0 '{"tool_name":"Bash","tool_input":{"command":"git stash list"}}'
guard 0 '{"tool_name":"Bash","tool_input":{"command":"git commit -m docs"}}'

echo; [ "$fails" -eq 0 ] && echo "smoke: all checks passed" || { echo "smoke: $fails check(s) failed"; exit 1; }
