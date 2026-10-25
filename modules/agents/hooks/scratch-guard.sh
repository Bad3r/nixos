# shellcheck shell=bash
# scratch and its regex-escaped scratchRe are prepended by scratch-guard.nix.
# shellcheck disable=SC2154
# PreToolUse hook: denies writes under /tmp, redirecting agents to $scratch,
# and new files directly in $scratch, which belong in a topic directory.
# Reads from /tmp stay allowed.
#
# Bash detection is a heuristic over the command text: it cannot see paths
# built at runtime or written by interpreters, and a /tmp path inside a quoted
# string or heredoc can trip it; the deny reason tells the agent how to retry.

input="$(cat)"
tool="$(jq -r '.tool_name // ""' <<<"$input")"
cwd="$(jq -r '.cwd // ""' <<<"$input")"

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

topicHint="$scratch/<topic>/ (one directory per task or session, named after it, e.g. the branch)"

# Pass create for tools that make a new file, so it cannot land loose in $scratch.
checkPath() {
  local path="$1" rest
  [ -n "$path" ] || return 0
  case "$path" in
  /*) ;;
  *) path="${cwd:-/}/$path" ;;
  esac
  path="$(realpath -ms -- "$path")"
  if isTmp "$path"; then
    rest="${path#/tmp}"
    case "$rest" in
    /*/*) ;;
    *) rest="/<topic>$rest" ;;
    esac
    deny "$path is under /tmp. Write to $scratch$rest instead (\$TMPDIR is $scratch), grouping files under $topicHint."
  fi
  if [ "${2-}" = create ] && [ "${path%/*}" = "$scratch" ]; then
    deny "$path would sit loose in $scratch. Write it under $topicHint, e.g. $scratch/<topic>/${path##*/}."
  fi
}

command="$(jq -r '.tool_input.command // ""' <<<"$input")"

# Codex apply_patch carries the patch text in tool_input.command.
if [ "$tool" = apply_patch ] || grep -q '^\*\*\* Begin Patch' <<<"$command"; then
  while IFS= read -r path; do
    checkPath "$path"
  done < <(sed -nE 's/^\*\*\* Update File: (.*)$/\1/p' <<<"$command")
  while IFS= read -r path; do
    checkPath "$path" create
  done < <(sed -nE 's/^\*\*\* (Add File|Move to): (.*)$/\2/p' <<<"$command")
  if [ "$tool" != Bash ]; then
    exit 0
  fi
fi

case "$tool" in
Write)
  checkPath "$(jq -r '.tool_input.file_path // ""' <<<"$input")" create
  exit 0
  ;;
Edit | MultiEdit | NotebookEdit)
  checkPath "$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$input")"
  exit 0
  ;;
Bash) ;;
*) exit 0 ;;
esac

# Splits a simple command into words; fails on unquoted shell operators,
# substitutions, comments, or newlines, which a word list cannot express.
splitWords() {
  local s="$1" c word="" quote="" i=0 inWord=0
  words=()
  while [ "$i" -lt "${#s}" ]; do
    c="${s:i:1}"
    i=$((i + 1))
    if [ "$quote" = "'" ]; then
      if [ "$c" = "'" ]; then quote=""; else word+="$c"; fi
      continue
    fi
    case "$c" in
    \\)
      [ "${s:i:1}" = $'\n' ] || word+="${s:i:1}"
      i=$((i + 1))
      ;;
    '"')
      if [ "$quote" = '"' ]; then quote=""; else quote='"'; fi
      ;;
    '`') return 1 ;;
    '$')
      [ "${s:i:1}" != "(" ] || return 1
      word+="$c"
      ;;
    *)
      if [ -n "$quote" ]; then
        word+="$c"
      else
        case "$c" in
        ' ' | $'\t')
          [ "$inWord" -eq 0 ] || words+=("$word")
          word="" inWord=0
          continue
          ;;
        "'") quote="'" ;;
        '|' | '&' | ';' | '<' | '>' | '(' | ')' | $'\n') return 1 ;;
        '#')
          [ "$inWord" -eq 1 ] || return 1
          word+="$c"
          ;;
        *) word+="$c" ;;
        esac
      fi
      ;;
    esac
    inWord=1
  done
  [ -z "$quote" ] || return 1
  [ "$inWord" -eq 0 ] || words+=("$word")
}

# splitWords keeps expansions literal, so a host target is resolved here the
# way the shell would, and refused when it cannot be.
# shellcheck disable=SC2016,SC2088
checkHostPath() {
  local path="$1"
  case "$path" in
  '$TMPDIR' | '$TMPDIR/'*) path="$scratch${path#'$TMPDIR'}" ;;
  '${TMPDIR}' | '${TMPDIR}/'*) path="$scratch${path#'${TMPDIR}'}" ;;
  '~' | '~/'*) path="$HOME${path#'~'}" ;;
  esac
  case "$path" in
  *[\$\`*?[]*) deny "Cannot resolve the sbx host path $1. Spell it out, or use \$TMPDIR/<topic> ($scratch/<topic>)." ;;
  esac
  checkPath "$path"
  if [ "$(realpath -ms -- "$path")" = "$scratch" ]; then
    deny "sbx would drop its output loose in $scratch. Copy it under $topicHint."
  fi
}

# Everything after exec or run's -- runs in the guest, whose /tmp is its own;
# only --to and a host cp destination write on the host.
if [[ $command =~ ^[[:space:]]*sbx[[:space:]] ]] && splitWords "$command"; then
  verb="" positional=()
  for ((n = 1; n < ${#words[@]}; n++)); do
    word="${words[n]}"
    case "$word" in
    --)
      case "$verb" in
      exec | run) ;;
      *) positional+=("${words[@]:n+1}") ;;
      esac
      break
      ;;
    --to)
      n=$((n + 1))
      checkHostPath "${words[n]-}"
      ;;
    --to=*) checkHostPath "${word#--to=}" ;;
    -*) ;;
    *) if [ -z "$verb" ]; then verb="$word"; else positional+=("$word"); fi ;;
    esac
  done
  if [ "$verb" = cp ] && [ "${#positional[@]}" -ge 2 ] &&
    ! grep -qE '^[a-z0-9][a-z0-9-]{0,30}:' <<<"${positional[1]}"; then
    checkHostPath "${positional[1]}"
  fi
  exit 0
fi

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
    deny "This command writes under /tmp. Use $scratch (\$TMPDIR) instead, e.g. $scratch/<topic>/<name>, grouping files under $topicHint; a bare mktemp suits throwaway files. If /tmp only appears in quoted text or as a read source, rephrase so no /tmp path sits in a write position. Guest paths of a bare sbx command (no pipes, redirections, && or env prefix) are not checked."
  fi
done

# Directories created in $scratch are topic directories; files belong inside one.
root="${q}(\\\$TMPDIR|\\\$\\{TMPDIR\\}|${scratchRe})${q}"
leaf="${root}/${q}[^/[:space:]\"';|&)<>]+${q}([[:space:];|&)<>]|$)"
patterns=(
  "(>>?|&>>?|>\|)[[:space:]]*${leaf}"
  "\btee\b${seg}[[:space:]]${leaf}"
  "\b(touch|truncate)\b${seg}[[:space:]]${leaf}"
  "\b(cp|mv|install|ln)\b${seg}[[:space:]]${root}/?${q}[[:space:]]*($|[|;&)])"
  "(^|[[:space:]])(-o|-O|--output|--output-document)(=|[[:space:]]+)${leaf}"
  "\bof=${leaf}"
)
for pattern in "${patterns[@]}"; do
  if grep -qE -- "$pattern" <<<"$command"; then
    deny "This command writes a file loose in $scratch (\$TMPDIR). Put it under $topicHint: mkdir -p \"\$TMPDIR/<topic>\" and write \$TMPDIR/<topic>/<name>."
  fi
done
exit 0
