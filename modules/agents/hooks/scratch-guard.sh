# shellcheck shell=bash
# PreToolUse hook: denies writes under /tmp, redirecting agents to /data/agents
# It denies rather than rewriting the path through updatedInput,
# so the agent knows where the file went. Reads from /tmp stay allowed.
#
# Bash detection is a heuristic over the command text: it cannot see paths
# built at runtime or written by interpreters, and a /tmp path inside a quoted
# string or heredoc can trip it; the deny reason tells the agent how to retry.

input="$(cat)"
tool="$(jq -r '.tool_name // ""' <<<"$input")"
cwd="$(jq -r '.cwd // ""' <<<"$input")"
scratch="/data/agents"

deny() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# X11 and ICE sockets are the only /tmp paths agents legitimately touch.
isTmp() {
  case "$1" in
  /tmp/.X11-unix | /tmp/.X11-unix/* | /tmp/.ICE-unix | /tmp/.ICE-unix/*) return 1 ;;
  /tmp | /tmp/*) return 0 ;;
  *) return 1 ;;
  esac
}

checkPath() {
  local path="$1"
  [ -n "$path" ] || return 0
  case "$path" in
  /*) ;;
  *) path="${cwd:-/}/$path" ;;
  esac
  path="$(realpath -ms -- "$path")"
  if isTmp "$path"; then
    deny "$path is under /tmp. Write to $scratch${path#/tmp} instead (\$TMPDIR is $scratch)."
  fi
}

command="$(jq -r '.tool_input.command // ""' <<<"$input")"

# Codex apply_patch carries the patch text in tool_input.command.
if [ "$tool" = apply_patch ] || grep -q '^\*\*\* Begin Patch' <<<"$command"; then
  while IFS= read -r path; do
    checkPath "$path"
  done < <(sed -nE 's/^\*\*\* (Add File|Update File|Move to): (.*)$/\2/p' <<<"$command")
  exit 0
fi

case "$tool" in
Write | Edit | MultiEdit | NotebookEdit)
  checkPath "$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$input")"
  exit 0
  ;;
Bash) ;;
*) exit 0 ;;
esac

# Mask the allowed sockets, then look for /tmp in a write position.
text="$(sed -E 's#/tmp/\.(X11|ICE)-unix#/allowed-socket#g' <<<"$command")"
q="[\"']?"
t="${q}/tmp(/|[\"'[:space:];|&)]|$)"
seg="[^|;&]*"
patterns=(
  "(>>?|&>>?|>\|)[[:space:]]*${t}"
  "\btee\b${seg}[[:space:]]${t}"
  "\b(mkdir|touch|mktemp|truncate|cd|pushd)\b${seg}[[:space:]=]${t}"
  "\bgit\b${seg}\b(clone|init|worktree[[:space:]]+add)\b${seg}[[:space:]]${t}"
  "\b(cp|mv|install|rsync|ln|scp)\b${seg}[[:space:]]${q}/tmp(/[^[:space:]|;&]*)?${q}[[:space:]]*($|[|;&)])"
  "\btar\b${seg}[[:space:]](-C|--directory)(=|[[:space:]]+)${t}"
  "\bunzip\b${seg}[[:space:]]-d[[:space:]]*${t}"
  "(^|[[:space:]])(-o|-O|-P|--output|--output-document|--directory-prefix|--target-directory|--tmpdir)(=|[[:space:]]+)${t}"
  "\bof=${t}"
  "(^|[[:space:]])[A-Za-z_][A-Za-z0-9_]*=${t}"
)
for pattern in "${patterns[@]}"; do
  if grep -qE -- "$pattern" <<<"$text"; then
    deny "This command writes under /tmp. Use $scratch (\$TMPDIR) instead, e.g. $scratch/<name> or a bare mktemp. If /tmp only appears in quoted text or as a read source, rephrase so no /tmp path sits in a write position."
  fi
done
exit 0
