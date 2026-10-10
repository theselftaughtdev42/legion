# Polly-specific smoke checks, sourced by scripts/smoke.sh (provides check, result, $name, $repo).

guard() {  # guard <expected exit> <hook json>
  printf "%s" "$2" | sbx exec -i "$name" bash -c 'WORKSPACE_DIR='"$repo"' bash /home/agent/.legion/guard.sh' >/dev/null 2>&1
  local rc=$?
  if [ "$rc" = "$1" ]; then result 0 "guard exit $1: $2"; else result 1 "guard exit $rc (want $1): $2"; fi
}

check "managed settings installed" "jq -e '.hooks.PreToolUse' /etc/claude-code/managed-settings.json"
check "Polly persona in managed memory" "grep -q 'You are \*\*Polly\*\*' /etc/claude-code/CLAUDE.md"

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
