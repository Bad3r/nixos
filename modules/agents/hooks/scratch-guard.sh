# shellcheck shell=bash
# scratch and its regex-escaped scratchRe are prepended by scratch-guard.nix.
# shellcheck disable=SC2154
# PreToolUse hook that keeps $scratch sorted: writes under /tmp, files loose in
# $scratch, and new top-level dirs without a task-like name are denied. The
# shell wrappers point $TMPDIR at $scratch/sessions/<root session id>; named
# work lives in $scratch/<topic>/. Reads from /tmp stay allowed.
#
# Bash detection is a heuristic over the command text: it cannot see paths
# built at runtime or written by interpreters, and a /tmp path inside a quoted
# string or heredoc can trip it; the deny reason tells the agent how to retry.

input="$(cat)"
tool="$(jq -r '.tool_name // ""' <<<"$input")"
cwd="$(jq -r '.cwd // ""' <<<"$input")"
sessionId="$(jq -r '.session_id // ""' <<<"$input")"

case "$sessionId" in
"" | *[!A-Za-z0-9-]*) sessionDir="" ;;
*) sessionDir="$scratch/sessions/$sessionId" ;;
esac

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

topicHint="files you name to the user, reuse in another session, or cite in memory go in $scratch/<topic>/, named after the PR, branch, or task"
if [ -n "$sessionDir" ]; then
  hint="Throwaway files go in this session's $sessionDir (\$TMPDIR in the shell, swept after a week idle); $topicHint."
else
  hint="${topicHint^}."
fi

# X11 and ICE sockets are the only /tmp paths agents legitimately touch.
isTmp() {
  case "$1" in
  /tmp/.X11-unix | /tmp/.X11-unix/* | /tmp/.ICE-unix | /tmp/.ICE-unix/*) return 1 ;;
  /tmp | /tmp/*) return 0 ;;
  *) return 1 ;;
  esac
}

# mktemp-style suffixes and IDs make a dir unfindable later.
badTopic() {
  local name="$1"
  case "$name" in
  sessions | tmp | temp | scratch | work | test | tests | out | output | misc | data | files | notes | logs | review | main | master | new | stuff) return 0 ;;
  esac
  [[ $name =~ ^[a-z0-9][a-z0-9._-]{1,63}$ ]] || return 0
  [[ $name =~ [0-9a-f]{8}-[0-9a-f]{4} ]] && return 0
  if [[ $name =~ [._-]([a-z0-9]{6,10})$ ]]; then
    local suffix="${BASH_REMATCH[1]}"
    [[ $suffix =~ [0-9] && $suffix =~ [a-z] ]] && return 0
  fi
  return 1
}

topicRule="Name a new top-level dir in $scratch after the PR, branch, or task: a lowercase slug (a-z, 0-9, . _ -), not a generic word, ID, or mktemp-style suffix."

# Pass create for tools that make a new file, so it lands in a session or topic dir.
checkPath() {
  local path="$1" rest top
  [ -n "$path" ] || return 0
  case "$path" in
  /*) ;;
  *) path="${cwd:-/}/$path" ;;
  esac
  path="$(realpath -ms -- "$path")"
  if isTmp "$path"; then
    rest="${path#/tmp}"
    case "$rest" in
    /*/*) deny "$path is under /tmp. Write to $scratch$rest instead. $hint" ;;
    *) deny "$path is under /tmp. Write to ${sessionDir:-$scratch/<topic>}$rest instead. $hint" ;;
    esac
  fi
  [ "${2-}" = create ] || return 0
  case "$path" in
  "$scratch"/*) ;;
  *) return 0 ;;
  esac
  rest="${path#"$scratch"/}"
  top="${rest%%/*}"
  if [ "$top" = "$rest" ]; then
    deny "$path would sit loose in $scratch. $hint"
  fi
  if [ "$top" = sessions ]; then
    rest="${rest#sessions/}"
    if [ "${rest%%/*}" = "$rest" ]; then
      deny "$path would sit loose in $scratch/sessions. $hint"
    fi
    if [ "$scratch/sessions/${rest%%/*}" != "$sessionDir" ] && [ ! -d "$scratch/sessions/${rest%%/*}" ]; then
      deny "$scratch/sessions/${rest%%/*} is not this session's dir; the shell wrappers create those. $hint"
    fi
  elif [ ! -e "$scratch/$top" ] && badTopic "$top"; then
    deny "$scratch/$top is not a findable name. $topicRule $hint"
  fi
}

# Session dirs are swept, so instructions and memory must not point into them.
isInstructionFile() {
  case "$1" in
  */CLAUDE.md | */AGENTS.md | */MEMORY.md | */memory/*.md | */memories/*) return 0 ;;
  *) return 1 ;;
  esac
}

checkCitation() {
  if isInstructionFile "$1" && grep -qF -- "$scratch/sessions/" <<<"$2"; then
    deny "$1 would cite a path under $scratch/sessions/, which is swept after a week idle. Move the file to $scratch/<topic>/ and cite that."
  fi
}

command="$(jq -r '.tool_input.command // ""' <<<"$input")"

# Codex apply_patch carries the patch text in tool_input.command.
if [ "$tool" = apply_patch ] || grep -q '^\*\*\* Begin Patch' <<<"$command"; then
  while IFS= read -r path; do
    checkPath "$path"
    checkCitation "$path" "$command"
  done < <(sed -nE 's/^\*\*\* Update File: (.*)$/\1/p' <<<"$command")
  while IFS= read -r path; do
    checkPath "$path" create
    checkCitation "$path" "$command"
  done < <(sed -nE 's/^\*\*\* (Add File|Move to): (.*)$/\2/p' <<<"$command")
  if [ "$tool" != Bash ]; then
    exit 0
  fi
fi

case "$tool" in
Write)
  file="$(jq -r '.tool_input.file_path // ""' <<<"$input")"
  checkPath "$file" create
  checkCitation "$file" "$(jq -r '.tool_input.content // ""' <<<"$input")"
  exit 0
  ;;
Edit | MultiEdit | NotebookEdit)
  file="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$input")"
  checkPath "$file"
  checkCitation "$file" "$(jq -r '[.tool_input.new_string // empty, (.tool_input.edits // [])[].new_string] | join("\n")' <<<"$input")"
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
  '$TMPDIR' | '$TMPDIR/'*) path="${sessionDir:-$scratch}${path#'$TMPDIR'}" ;;
  '${TMPDIR}' | '${TMPDIR}/'*) path="${sessionDir:-$scratch}${path#'${TMPDIR}'}" ;;
  '~' | '~/'*) path="$HOME${path#'~'}" ;;
  esac
  case "$path" in
  *[\$\`*?[]*) deny "Cannot resolve the sbx host path $1. Spell it out. $hint" ;;
  esac
  checkPath "$path"
  if [ "$(realpath -ms -- "$path")" = "$scratch" ]; then
    deny "sbx would drop its output loose in $scratch. $hint"
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
    deny "This command writes under /tmp. $hint A bare mktemp lands in \$TMPDIR. If /tmp only appears in quoted text or as a read source, rephrase so no /tmp path sits in a write position. Guest paths of a bare sbx command (no pipes, redirections, && or env prefix) are not checked."
  fi
done

# $TMPDIR is the session dir, so only literal $scratch paths can land loose.
root="${q}${scratchRe}${q}"
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
    deny "This command writes a file loose in $scratch. $hint"
  fi
done

# A writing command may create any top-level dir it names.
if grep -qE '>|\b(mkdir|git|cp|mv|rsync|install|ln|tar|unzip|curl|wget|touch|tee)\b' <<<"$command"; then
  while IFS= read -r top; do
    if [ ! -e "$scratch/$top" ] && badTopic "$top"; then
      deny "$scratch/$top is not a findable name. $topicRule $hint"
    fi
  done < <(grep -oE "${scratchRe}/[^/[:space:]\"';|&)<>\$\`]+" <<<"$command" | sed "s#^$scratch/##" | sort -u)
fi
exit 0
