# shellcheck shell=bash
# decision (ask or deny) is prepended by sbx-approval.nix.
# shellcheck disable=SC2154
# PreToolUse hook: an sbx sandbox with egress, or the read-write shared
# directory, needs the owner's approval; offline sandboxes and read-only
# shares pass.
#
# Bash detection is a heuristic over the command text: in a command that
# names sbx, any --net value but a literal none counts, and so does a share
# attach whose tag is shared or not a literal.

input="$(cat)"
tool="$(jq -r '.tool_name // ""' <<<"$input")"

gate() {
  local reason="$1"
  if [ "$decision" = deny ]; then
    reason+=" Codex hooks cannot ask the owner, so hand them the exact command to run, or stay offline."
  fi
  jq -n --arg decision "$decision" --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: $decision,
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

egress="This sbx sandbox gets internet egress, so anything copied into it can leave the host."
share="This attaches the read-write shared directory, so the guest writes files on the host."

case "$tool" in
mcp__sbx__create | mcp__sbx__run)
  [ "$(jq -r '.tool_input.net // "none"' <<<"$input")" = none ] || gate "$egress"
  exit 0
  ;;
Bash) ;;
*) exit 0 ;;
esac

command="$(jq -r '.tool_input.command // ""' <<<"$input")"
command="${command//$'\\\n'/ }"
case "$command" in
*sbx*) ;;
*) exit 0 ;;
esac

# argparse takes --ne for --net.
while IFS= read -r value; do
  value="${value//[\"\']/}"
  [ "$value" = none ] || gate "$egress"
done < <(grep -oE -- '--net?(=|[[:space:]]+)[^[:space:];|&)]*' <<<"$command" | sed -E 's/^--net?(=|[[:space:]]+)//')

while IFS= read -r attach; do
  read -ra words <<<"$attach"
  for word in "${words[@]:2}"; do
    word="${word//[\"\']/}"
    case "$word" in
    shared | *[\$\`]*) gate "$share" ;;
    esac
  done
done < <(grep -oE '\bshare[[:space:]]+attach([[:space:]]+[^[:space:];|&)]+)+' <<<"$command")
exit 0
