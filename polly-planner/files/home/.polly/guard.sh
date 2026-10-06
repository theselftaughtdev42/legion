#!/usr/bin/env bash
# PreToolUse guard for Polly: file edits only on domain docs, no destructive git.
# Exit 2 blocks the tool call and feeds stderr back to Claude.
set -euo pipefail

input=$(cat)
tool=$(jq -r '.tool_name' <<<"$input")
ws=$(realpath -m "${WORKSPACE_DIR:-$(jq -r '.cwd' <<<"$input")}")

block() { echo "Polly guard: $*" >&2; exit 2; }

case "$tool" in
  Bash)
    cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
    # Read-only stash subcommands are fine; anything else that stashes is not.
    stripped=$(sed -E 's/git[[:space:]]+stash[[:space:]]+(list|show)//g' <<<"$cmd")
    if grep -Eq 'git[[:space:]].*(reset[[:space:]]+--hard|checkout[[:space:]]+--|restore[[:space:]]|stash|clean[[:space:]]+-|push[[:space:]].*(--force|-f\b))' <<<"$stripped"; then
      block "destructive git commands are not allowed (reset --hard, checkout --, restore, stash, clean, force push). This is the user's real checkout."
    fi
    ;;
  *)
    path=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$input")
    [ -n "$path" ] || exit 0
    case "$path" in /*) ;; *) path="$ws/$path" ;; esac
    path=$(realpath -m "$path")
    case "$path" in
      "$ws"/*) rel=${path#"$ws"/} ;;
      /home/agent/polly/*) exit 0 ;;   # private scratch space
      *) block "$path is outside the workspace." ;;
    esac
    case "$rel" in
      GLOSSARY.md|GLOSSARY-MAP.md|*/GLOSSARY.md|docs/adr/*|*/docs/adr/*|docs/agents/*|CLAUDE.md|AGENTS.md) exit 0 ;;
      *) block "Polly only edits domain docs (GLOSSARY*.md, docs/adr/, docs/agents/, CLAUDE.md, AGENTS.md); '$rel' is off limits. Capture code changes in the spec/tickets instead." ;;
    esac
    ;;
esac
exit 0
