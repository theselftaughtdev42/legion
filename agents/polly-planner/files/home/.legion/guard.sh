#!/usr/bin/env bash
# PreToolUse guard for Polly: file edits only on domain docs, no destructive git.
# Exit 2 blocks the tool call and feeds stderr back to Claude.
set -euo pipefail
set -f   # disable globbing: several checks below word-split raw command text

input=$(cat)
tool=$(jq -r '.tool_name' <<<"$input")
ws=$(realpath -m "${WORKSPACE_DIR:-$(jq -r '.cwd' <<<"$input")}")

block() { echo "Polly guard: $*" >&2; exit 2; }

# Resolve $1 (absolute, or relative to $ws) and enforce the domain-docs
# allowlist. Scratch space under /home/agent/polly/ is always allowed.
check_path() {
  local path="$1" rel
  case "$path" in /*) ;; *) path="$ws/$path" ;; esac
  path=$(realpath -m "$path")
  case "$path" in
    "$ws"/*) rel=${path#"$ws"/} ;;
    /home/agent/polly/*) return 0 ;;
    *) block "$path is outside the workspace." ;;
  esac
  case "$rel" in
    GLOSSARY.md|GLOSSARY-MAP.md|*/GLOSSARY.md|*/GLOSSARY-MAP.md|docs/adr/*|*/docs/adr/*|docs/agents/*|*/docs/agents/*|CLAUDE.md|*/CLAUDE.md|AGENTS.md|*/AGENTS.md) return 0 ;;
    *) block "Polly only edits domain docs (GLOSSARY*.md, docs/adr/, docs/agents/, CLAUDE.md, AGENTS.md); '$rel' is off limits. Capture code changes in the spec/tickets instead." ;;
  esac
}

case "$tool" in
  Bash)
    cmd=$(jq -r '.tool_input.command // ""' <<<"$input")

    # Read-only stash subcommands are fine; anything else that stashes is not.
    stripped=$(sed -E 's/git[[:space:]]+stash[[:space:]]+(list|show)//g' <<<"$cmd")
    if grep -Eq 'git[[:space:]].*(reset[[:space:]]+--hard|checkout[[:space:]]+--|restore[[:space:]]|stash|clean[[:space:]]+-|push[[:space:]].*(--force|-f\b))' <<<"$stripped"; then
      block "destructive git commands are not allowed (reset --hard, checkout --, restore, stash, clean, force push). This is the user's real checkout."
    fi

    # In-place sed is just as much an arbitrary-file-write as cp/tee/>, but
    # its target is the last of a variable number of args -- simpler to
    # disallow it outright than to parse it out.
    if grep -Eq '(^|[;&|[:space:]])sed[[:space:]]+(-[a-zA-Z]*i|--in-place)' <<<"$cmd"; then
      block "in-place edits (sed -i) are not allowed; edit domain docs with the Edit/Write tools instead."
    fi

    # Best-effort scan: anything that writes, copies, moves, links, or
    # deletes a file must target an allowed path, same as Edit/Write. This
    # is regex over raw text, not a real shell parser -- quoting,
    # variables, and command substitution can still evade it -- but it
    # closes the plain-text bypass where Bash was used to touch files the
    # Edit/Write check would have blocked outright.
    while IFS= read -r clause; do
      [ -n "$clause" ] || continue
      rest=$(sed -E 's/^[;&|[:space:]]*[^[:space:]]+[[:space:]]+//' <<<"$clause")
      for tok in $rest; do
        case "$tok" in -*) continue ;; esac
        check_path "$tok"
      done
    done < <(grep -Eo '(^|[;&|[:space:]])(cp|mv|rm|rmdir|tee|touch|ln|install|mkdir|rsync|patch)[[:space:]]+[^;&|]*' <<<"$cmd")

    # Output redirection (>, >>, &>, &>>, optionally fd-prefixed). Skip pure
    # fd-duplication targets like the "1" in "2>&1".
    while IFS= read -r target; do
      case "$target" in ''|[0-9]) continue ;; esac
      check_path "$target"
    done < <(grep -Eo '(&>{1,2}|[0-9]?>{1,2})[[:space:]]*[^[:space:];&|)]+' <<<"$cmd" \
        | sed -E 's/^(&>{1,2}|[0-9]?>{1,2})[[:space:]]*//')
    ;;
  *)
    path=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$input")
    [ -n "$path" ] || exit 0
    check_path "$path"
    ;;
esac
exit 0
