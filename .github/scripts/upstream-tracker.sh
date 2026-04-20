#!/usr/bin/env bash
# shellcheck shell=bash
# upstream-tracker.sh - reconcile `status(blocked-upstream)` issues with upstream state.
#
# Usage:
#   .github/scripts/upstream-tracker.sh [<issue-number>]
#
# Env:
#   GH_TOKEN                          required for live runs; `gh api` honours it.
#   UPSTREAM_TRACKER_DRY_RUN=1        do not post comments or edit labels; print
#                                     what would happen.
#   UPSTREAM_TRACKER_OFFLINE_MOCKS    directory of mock JSON files; read instead
#                                     of calling `gh api`. File layout:
#                                       <mock_dir>/<path-with-slashes-as-__>.json
#                                     Each file wraps {"status": N, "body": ...}.
#                                     Combined with PARSE_ONLY this gates the
#                                     test harness from hitting the live API.
#   UPSTREAM_TRACKER_OFFLINE_STRICT=1 missing mock becomes a hard error.
#   UPSTREAM_TRACKER_PARSE_ONLY=1     read one issue body from stdin, run the
#                                     full parse + probe + compose pipeline, and
#                                     emit the decision JSON to stdout. No side
#                                     effects. Used by the test harness.

set -euo pipefail

BLOCKED_LABEL="status(blocked-upstream)"
READY_LABEL="status(ready-to-unblock)"
MARKER_DIGEST="<!-- upstream-tracker v1 -->"
MARKER_PARSE="<!-- upstream-tracker v1 parse -->"

# ----- shared helpers ---------------------------------------------------------

log() {
  printf '%s\n' "$*" >&2
}

warn() {
  printf 'upstream-tracker: warn: %s\n' "$*" >&2
}

die() {
  printf 'upstream-tracker: error: %s\n' "$*" >&2
  exit 1
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

sig() {
  printf '%s' "$1" | sha1sum | cut -c1-12
}

utc_now() {
  if [[ -n ${UPSTREAM_TRACKER_FAKE_NOW:-} ]]; then
    printf '%s' "$UPSTREAM_TRACKER_FAKE_NOW"
  else
    date -u +'%Y-%m-%dT%H:%MZ'
  fi
}

is_dry_run() {
  [[ ${UPSTREAM_TRACKER_DRY_RUN:-0} == "1" ]]
}

is_parse_only() {
  [[ ${UPSTREAM_TRACKER_PARSE_ONLY:-0} == "1" ]]
}

# mock-lookup slug: POSIX path → underscore-joined string with reserved-char
# substitutions so every file name is filesystem-safe across platforms.
slug_path() {
  local input="$1"
  input="${input//\//__}"
  input="${input//\?/__Q__}"
  input="${input//\&/__A__}"
  input="${input//=/__E__}"
  printf '%s' "$input"
}

# ----- gh api wrapper ---------------------------------------------------------

gh_api() {
  local path="$1"
  shift || true
  if [[ -n ${UPSTREAM_TRACKER_OFFLINE_MOCKS:-} ]]; then
    local slug
    slug="$(slug_path "$path")"
    local mock_file="${UPSTREAM_TRACKER_OFFLINE_MOCKS}/${slug}.json"
    if [[ -f $mock_file ]]; then
      local status
      status="$(jq -r '.status // 200' "$mock_file")"
      jq '.body // empty' "$mock_file"
      if [[ $status =~ ^[0-9]+$ ]] && ((status >= 200 && status < 300)); then
        return 0
      fi
      return 22
    fi
    if [[ ${UPSTREAM_TRACKER_OFFLINE_STRICT:-0} == "1" ]]; then
      warn "missing mock for gh api $path (looked at $mock_file)"
      return 77
    fi
  fi
  gh api "$path" "$@" 2>/dev/null
}

# ----- parser -----------------------------------------------------------------

# split_sections emits tab-separated "section\tline" for every body line; the
# section is empty for content above the first `### <label>` heading.
split_sections() {
  awk 'BEGIN { section = "" }
    /^### / { section = substr($0, 5); next }
    { print section "\t" $0 }'
}

# extract_section prints the lines of one section (without the heading).
extract_section() {
  local body="$1" label="$2"
  printf '%s\n' "$body" | split_sections |
    awk -F '\t' -v lbl="$label" '$1 == lbl { print $2 }'
}

# split_url_and_note takes "<url> - <note>" and emits two US-separated tokens.
# Accepts ASCII hyphen, em-dash, or double-hyphen as the separator.
split_url_and_note() {
  local raw="$1"
  local url="$raw" note=""
  if [[ $raw =~ ^([^[:space:]]+)[[:space:]]+[-—]+[[:space:]]+(.*)$ ]]; then
    url="${BASH_REMATCH[1]}"
    note="${BASH_REMATCH[2]}"
  fi
  printf '%s\x1f%s' "$url" "$note"
}

# classify_url emits "kind<US>owner<US>repo<US>identifier" for a supported URL
# shape, or four empty fields separated by <US> (\x1f) if unsupported.
classify_url() {
  local url="$1"
  local re='^https://github\.com/([^/]+)/([^/]+)/(.+)$'
  if [[ $url =~ ^https://github\.com/([^/]+)/([^/]+)/?$ ]]; then
    # Bare repo URL is not a supported shape.
    printf '\x1f\x1f\x1f'
    return 0
  fi
  if [[ ! $url =~ $re ]]; then
    printf '\x1f\x1f\x1f'
    return 0
  fi
  local owner="${BASH_REMATCH[1]}"
  local repo="${BASH_REMATCH[2]}"
  local tail="${BASH_REMATCH[3]}"
  case "$tail" in
  pull/[0-9]*) printf 'pr\x1f%s\x1f%s\x1f%s' "$owner" "$repo" "${tail#pull/}" ;;
  issues/[0-9]*) printf 'issue\x1f%s\x1f%s\x1f%s' "$owner" "$repo" "${tail#issues/}" ;;
  releases/tag/*) printf 'release-tag\x1f%s\x1f%s\x1f%s' "$owner" "$repo" "${tail#releases/tag/}" ;;
  releases) printf 'release-stream\x1f%s\x1f%s\x1f' "$owner" "$repo" ;;
  tree/*) printf 'tree-ref\x1f%s\x1f%s\x1f%s' "$owner" "$repo" "${tail#tree/}" ;;
  *) printf '\x1f\x1f\x1f' ;;
  esac
}

# parse_note inspects a free-form note and returns:
#   sub_kind\tmin_version\tcontains_sha\tcontains_owner\tcontains_repo\tref_type
# sub_kind ∈ { "", "version", "contains", "ref-type-tag" }.
parse_note() {
  local note="$1"
  local sub_kind="" min_version="" contains_sha="" contains_owner="" contains_repo="" ref_type=""
  local nocase_was_set=0
  if shopt -q nocasematch; then
    nocase_was_set=1
  fi
  shopt -s nocasematch
  if [[ $note =~ target[[:space:]]*\>=[[:space:]]*([vV]?[0-9][0-9a-zA-Z.+_-]*) ]]; then
    sub_kind="version"
    min_version="${BASH_REMATCH[1]}"
    min_version="${min_version#v}"
    min_version="${min_version#V}"
  fi
  if [[ $note =~ contains[[:space:]]+(([^[:space:]@]+)@)?([0-9a-fA-F]{40}) ]]; then
    local ownerrepo="${BASH_REMATCH[2]}"
    local sha="${BASH_REMATCH[3]}"
    if [[ -n $ownerrepo && $ownerrepo =~ ^([^/]+)/([^/]+)$ ]]; then
      contains_owner="${BASH_REMATCH[1]}"
      contains_repo="${BASH_REMATCH[2]}"
    fi
    contains_sha="$(printf '%s' "$sha" | tr '[:upper:]' '[:lower:]')"
    if [[ -z $sub_kind ]]; then
      sub_kind="contains"
    fi
  fi
  if [[ $note =~ ref-type[[:space:]:=]+tag ]]; then
    ref_type="tag"
    if [[ -z $sub_kind ]]; then
      sub_kind="ref-type-tag"
    fi
  fi
  if [[ $nocase_was_set -eq 0 ]]; then
    shopt -u nocasematch
  fi
  printf '%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s' \
    "$sub_kind" "$min_version" "$contains_sha" "$contains_owner" "$contains_repo" "$ref_type"
}

# parse_issue_body consumes the issue body on stdin and emits two arrays on
# stdout as `{"refs": [...], "warnings": [...]}` JSON.
parse_issue_body() {
  local body
  body="$(cat)"

  local -a refs_array=()
  local -a warnings=()

  # audit: Type / Scope
  local t_val s_val
  t_val="$(extract_section "$body" "Type" | awk 'NF { print; exit }')"
  s_val="$(extract_section "$body" "Scope" | awk 'NF { print; exit }')"
  [[ -z $t_val ]] && warnings+=("Type section is empty")
  [[ -z $s_val ]] && warnings+=("Scope section is empty")

  local section
  for section in "Upstream pull requests" "Upstream issues" "Upstream releases and channels"; do
    local section_body
    section_body="$(extract_section "$body" "$section")"

    local has_none=0
    local -a raw_lines=()
    local line
    while IFS= read -r line; do
      local trimmed="${line## }"
      trimmed="${trimmed%% }"
      [[ -z $trimmed ]] && continue
      case "$trimmed" in
      "_No response_") : ;;
      "none" | "None" | "NONE") has_none=1 ;;
      *) raw_lines+=("$trimmed") ;;
      esac
    done <<<"$section_body"

    if [[ ${#raw_lines[@]} -gt 0 && $has_none -eq 1 ]]; then
      warnings+=("$section: \`none\` appears alongside URLs; URLs will still be parsed")
    fi

    local raw
    for raw in "${raw_lines[@]:-}"; do
      [[ -z $raw ]] && continue
      local role url note role_re rest
      role_re='^(blocker|fix|related|superseded)[[:space:]]+(.*)$'
      if [[ ! $raw =~ $role_re ]]; then
        warnings+=("$section: line does not start with a role keyword: \`$raw\`")
        continue
      fi
      role="${BASH_REMATCH[1]}"
      rest="${BASH_REMATCH[2]}"
      local un
      un="$(split_url_and_note "$rest")"
      url="${un%%$'\x1f'*}"
      note="${un#*$'\x1f'}"
      if [[ -z $url || ! $url =~ ^https://github\.com/ ]]; then
        warnings+=("$section: expected full GitHub URL, got: \`$rest\`")
        continue
      fi

      local class owner repo identifier kind
      class="$(classify_url "$url")"
      IFS=$'\x1f' read -r kind owner repo identifier <<<"$class"
      if [[ -z $kind ]]; then
        warnings+=("$section: unrecognised URL shape: \`$url\`")
        continue
      fi

      local sub_kind min_version contains_sha contains_owner contains_repo ref_type
      IFS=$'\x1f' read -r sub_kind min_version contains_sha contains_owner contains_repo ref_type \
        <<<"$(parse_note "$note")"

      local probe_kind=""
      case "$kind" in
      pr) probe_kind="pr" ;;
      issue) probe_kind="issue" ;;
      release-tag) probe_kind="release-tag" ;;
      release-stream)
        case "$sub_kind" in
        version) probe_kind="release-stream-version" ;;
        contains) probe_kind="release-stream-contains" ;;
        *)
          warnings+=("$section: releases URL \`$url\` needs \`target >= X.Y.Z\` or \`contains OWNER/REPO@<sha>\`; skipping")
          continue
          ;;
        esac
        if [[ $sub_kind == "version" && -n $contains_sha ]]; then
          warnings+=("$section: releases URL \`$url\` has both \`target >=\` and \`contains @sha\`; using \`target >=\`")
        fi
        ;;
      tree-ref)
        case "$sub_kind" in
        ref-type-tag) probe_kind="tree-tag" ;;
        contains) probe_kind="tree-branch-sha" ;;
        *)
          warnings+=("$section: tree URL \`$url\` needs \`ref-type tag\` or \`contains OWNER/REPO@<sha>\`; skipping")
          continue
          ;;
        esac
        ;;
      esac

      if [[ -n $contains_owner && -n $owner ]]; then
        local ulo uro clo cro
        ulo="$(printf '%s' "$owner" | tr '[:upper:]' '[:lower:]')"
        uro="$(printf '%s' "$repo" | tr '[:upper:]' '[:lower:]')"
        clo="$(printf '%s' "$contains_owner" | tr '[:upper:]' '[:lower:]')"
        cro="$(printf '%s' "$contains_repo" | tr '[:upper:]' '[:lower:]')"
        if [[ $clo != "$ulo" || $cro != "$uro" ]]; then
          warnings+=("$section: \`contains $contains_owner/$contains_repo@...\` repo differs from URL \`$owner/$repo\`; still polling against URL repo")
        fi
      fi

      local rec
      rec="$(jq -cn \
        --arg section "$section" \
        --arg role "$role" \
        --arg url "$url" \
        --arg note "$note" \
        --arg kind "$probe_kind" \
        --arg owner "$owner" \
        --arg repo "$repo" \
        --arg identifier "$identifier" \
        --arg sub_kind "$sub_kind" \
        --arg min_version "$min_version" \
        --arg contains_sha "$contains_sha" \
        --arg ref_type "$ref_type" \
        '{section:$section, role:$role, url:$url, note:$note, kind:$kind,
          owner:$owner, repo:$repo, identifier:$identifier,
          sub_kind:$sub_kind, min_version:$min_version,
          contains_sha:$contains_sha, ref_type:$ref_type}')"
      refs_array+=("$rec")
    done
  done

  local refs_arr warnings_arr
  if [[ ${#refs_array[@]} -gt 0 ]]; then
    refs_arr="$(printf '%s\n' "${refs_array[@]}" | jq -s '.')"
  else
    refs_arr="[]"
  fi
  if [[ ${#warnings[@]} -gt 0 ]]; then
    warnings_arr="$(printf '%s\n' "${warnings[@]}" | jq -R . | jq -s '.')"
  else
    warnings_arr="[]"
  fi

  jq -cn --argjson refs "$refs_arr" --argjson warnings "$warnings_arr" \
    '{refs:$refs, warnings:$warnings}'
}

# ----- probes -----------------------------------------------------------------

# semver_ge a b -> exit 0 if a >= b by `sort -V`.
semver_ge() {
  local a="$1" b="$2"
  [[ $a == "$b" ]] && return 0
  local first
  first="$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -n 1)"
  [[ $first == "$b" ]]
}

api_or_die() {
  local out rc=0
  out="$(gh_api "$@")" || rc=$?
  if [[ $rc -ne 0 ]]; then
    printf '__upstream_tracker_missing__'
    return 0
  fi
  printf '%s' "$out"
}

probe_pr() {
  local owner="$1" repo="$2" num="$3" out state merged
  out="$(api_or_die "repos/$owner/$repo/pulls/$num")"
  if [[ $out == "__upstream_tracker_missing__" ]]; then
    printf 'missing\n'
    return 0
  fi
  state="$(printf '%s' "$out" | jq -r '.state // empty')"
  merged="$(printf '%s' "$out" | jq -r '.merged // false')"
  if [[ $state == "closed" ]]; then
    if [[ $merged == "true" ]]; then
      printf 'merged\n'
    else
      printf 'closed-unmerged\n'
    fi
    return 0
  fi
  printf 'open\n'
}

probe_issue() {
  local owner="$1" repo="$2" num="$3" out state
  out="$(api_or_die "repos/$owner/$repo/issues/$num")"
  if [[ $out == "__upstream_tracker_missing__" ]]; then
    printf 'missing\n'
    return 0
  fi
  state="$(printf '%s' "$out" | jq -r '.state // empty')"
  if [[ $state == "closed" ]]; then
    printf 'closed\n'
    return 0
  fi
  printf 'open\n'
}

probe_release_tag() {
  local owner="$1" repo="$2" tag="$3" out
  out="$(api_or_die "repos/$owner/$repo/releases/tags/$tag")"
  if [[ $out == "__upstream_tracker_missing__" ]]; then
    printf 'missing\n'
    return 0
  fi
  printf 'released\n'
}

probe_release_stream_version() {
  local owner="$1" repo="$2" min="$3" out tag strip
  out="$(api_or_die "repos/$owner/$repo/releases?per_page=30")"
  if [[ $out == "__upstream_tracker_missing__" ]]; then
    printf 'missing\n'
    return 0
  fi
  while IFS= read -r tag; do
    [[ -z $tag ]] && continue
    strip="${tag#v}"
    strip="${strip#V}"
    if semver_ge "$strip" "$min"; then
      printf 'released:%s\n' "$tag"
      return 0
    fi
  done < <(printf '%s' "$out" | jq -r '.[].tag_name // empty')
  printf 'pending\n'
}

probe_release_stream_contains() {
  local owner="$1" repo="$2" sha="$3" out tags tag cmp status
  out="$(api_or_die "repos/$owner/$repo/tags?per_page=100")"
  if [[ $out == "__upstream_tracker_missing__" ]]; then
    printf 'missing\n'
    return 0
  fi
  tags="$(printf '%s' "$out" | jq -r '.[].name // empty')"
  while IFS= read -r tag; do
    [[ -z $tag ]] && continue
    cmp="$(api_or_die "repos/$owner/$repo/compare/$sha...$tag")"
    [[ $cmp == "__upstream_tracker_missing__" ]] && continue
    status="$(printf '%s' "$cmp" | jq -r '.status // empty')"
    case "$status" in
    ahead | identical)
      printf 'contained-in:%s\n' "$tag"
      return 0
      ;;
    esac
  done <<<"$tags"
  printf 'pending\n'
}

probe_plain_tag() {
  local owner="$1" repo="$2" tag="$3" out
  out="$(api_or_die "repos/$owner/$repo/git/ref/tags/$tag")"
  if [[ $out == "__upstream_tracker_missing__" ]]; then
    printf 'missing\n'
    return 0
  fi
  printf 'released\n'
}

probe_branch_sha() {
  local owner="$1" repo="$2" branch="$3" sha="$4" out status
  out="$(api_or_die "repos/$owner/$repo/compare/$sha...$branch")"
  if [[ $out == "__upstream_tracker_missing__" ]]; then
    printf 'missing\n'
    return 0
  fi
  status="$(printf '%s' "$out" | jq -r '.status // empty')"
  case "$status" in
  ahead | identical) printf 'contained\n' ;;
  *) printf 'pending\n' ;;
  esac
}

probe_ref() {
  local ref_json="$1"
  local kind owner repo identifier sub_kind min_version contains_sha
  kind="$(jq -r '.kind' <<<"$ref_json")"
  owner="$(jq -r '.owner' <<<"$ref_json")"
  repo="$(jq -r '.repo' <<<"$ref_json")"
  identifier="$(jq -r '.identifier' <<<"$ref_json")"
  sub_kind="$(jq -r '.sub_kind' <<<"$ref_json")"
  min_version="$(jq -r '.min_version' <<<"$ref_json")"
  contains_sha="$(jq -r '.contains_sha' <<<"$ref_json")"
  case "$kind" in
  pr) probe_pr "$owner" "$repo" "$identifier" ;;
  issue) probe_issue "$owner" "$repo" "$identifier" ;;
  release-tag) probe_release_tag "$owner" "$repo" "$identifier" ;;
  release-stream-version) probe_release_stream_version "$owner" "$repo" "$min_version" ;;
  release-stream-contains) probe_release_stream_contains "$owner" "$repo" "$contains_sha" ;;
  tree-tag) probe_plain_tag "$owner" "$repo" "$identifier" ;;
  tree-branch-sha) probe_branch_sha "$owner" "$repo" "$identifier" "$contains_sha" ;;
  *) printf 'unknown\n' ;;
  esac
}

# resolved predicate: true when the probe reports a terminal resolved state.
is_resolved_state() {
  local state="$1"
  case "$state" in
  merged | closed | released | released:* | contained | contained-in:* | closed-unmerged)
    return 0
    ;;
  esac
  return 1
}

# pretty label for a resolved state in the digest.
state_label() {
  local state="$1"
  case "$state" in
  merged) printf 'merged' ;;
  closed) printf 'closed' ;;
  closed-unmerged) printf 'closed without merge' ;;
  released) printf 'released' ;;
  released:*) printf 'released (%s)' "${state#released:}" ;;
  contained) printf 'contained' ;;
  contained-in:*) printf 'contained in %s' "${state#contained-in:}" ;;
  *) printf '%s' "$state" ;;
  esac
}

# ----- comment dedupe ---------------------------------------------------------

collect_seen_sigs() {
  local issue="$1"
  if [[ -z $issue ]] || is_parse_only; then
    return 0
  fi
  local raw
  if ! raw="$(gh issue view "$issue" --json comments --jq '.comments[].body' 2>/dev/null)"; then
    return 0
  fi
  printf '%s' "$raw" |
    grep -oE 'sig=[0-9a-f]{12}' |
    sort -u ||
    true
}

# ----- digest composition -----------------------------------------------------

compose_digest_body() {
  local ts="$1" refs_json="$2" blockers_total="$3" blockers_resolved="$4"
  local run_sig
  run_sig="$(
    jq -r '
      map(.role + "|" + .url + "|" + .kind + "|" + .state) | sort | .[]
    ' <<<"$refs_json" | sig "$(cat)"
  )"
  if [[ -z $run_sig ]]; then
    run_sig="$(printf '%s' "$ts" | sig "$(cat)")"
  fi

  local ref_sigs
  ref_sigs="$(jq -r '.[].sig // empty' <<<"$refs_json" | awk 'NF {print "sig=" $0}' | tr '\n' ' ')"
  ref_sigs="${ref_sigs% }"

  {
    printf '%s sig=%s\n' "$MARKER_DIGEST" "$run_sig"
    [[ -n $ref_sigs ]] && printf '<!-- refs: %s -->\n' "$ref_sigs"
    printf 'Upstream state changes detected on %s:\n\n' "$ts"
    jq -r '.[] | "- " + .role + " **" + .label + "** " + .url' <<<"$refs_json"
    if [[ $blockers_total -gt 0 ]]; then
      printf '\n'
      if [[ $blockers_resolved -eq $blockers_total ]]; then
        # shellcheck disable=SC2016 # literal backticks for Markdown code spans
        printf 'Label swapped: `%s` → `%s`.\n' "$BLOCKED_LABEL" "$READY_LABEL"
        # shellcheck disable=SC2016 # literal backticks for Markdown code spans
        printf '(%s of %s `blocker` references resolved.)\n' "$blockers_resolved" "$blockers_total"
      else
        # shellcheck disable=SC2016 # literal backticks for Markdown code spans
        printf '`blocker` progress: %s of %s resolved — label unchanged.\n' \
          "$blockers_resolved" "$blockers_total"
      fi
    fi
  }
}

compose_warning_body() {
  local ts="$1" warnings_json="$2"
  local joined warn_sig
  joined="$(jq -r '.[]' <<<"$warnings_json" | sort)"
  warn_sig="$(printf '%s' "$joined" | sig "$(cat)")"
  {
    printf '%s sig=%s\n' "$MARKER_PARSE" "$warn_sig"
    printf 'Template drift detected on %s:\n\n' "$ts"
    printf '%s\n' "$joined" | awk 'NF { print "- " $0 }'
  }
}

# ----- label transition -------------------------------------------------------

transition_label() {
  local issue="$1"
  if is_dry_run || is_parse_only; then
    printf '[dry-run] would relabel #%s: remove %s, add %s\n' "$issue" "$BLOCKED_LABEL" "$READY_LABEL" >&2
    return 0
  fi
  gh issue edit "$issue" \
    --remove-label "$BLOCKED_LABEL" \
    --add-label "$READY_LABEL" >/dev/null 2>&1 ||
    warn "failed to swap label on #$issue (non-fatal)"
}

emit_comment() {
  local issue="$1" body="$2" kind="$3"
  if is_dry_run || is_parse_only; then
    printf '[dry-run] would comment on #%s (%s):\n' "$issue" "$kind" >&2
    printf '%s\n' "$body" >&2
    return 0
  fi
  gh issue comment "$issue" --body "$body" >/dev/null
}

# ----- issue processing -------------------------------------------------------

process_issue_body() {
  local issue="$1" body="$2"
  local parsed refs_json warnings_json
  parsed="$(printf '%s' "$body" | parse_issue_body)"
  refs_json="$(jq -c '.refs' <<<"$parsed")"
  warnings_json="$(jq -c '.warnings' <<<"$parsed")"

  # probe every ref; enrich with state + sig + label.
  local enriched="[]"
  local len
  len="$(jq 'length' <<<"$refs_json")"
  local i ref state resolved sig_val label
  for ((i = 0; i < len; i++)); do
    ref="$(jq -c ".[$i]" <<<"$refs_json")"
    state="$(probe_ref "$ref")"
    if is_resolved_state "$state"; then resolved=true; else resolved=false; fi
    sig_val="$(printf '%s|%s|%s|%s' \
      "$(jq -r '.role' <<<"$ref")" \
      "$(jq -r '.url' <<<"$ref")" \
      "$(jq -r '.kind' <<<"$ref")" \
      "$state" | sig "$(cat)")"
    label="$(state_label "$state")"
    ref="$(jq -c \
      --arg state "$state" \
      --argjson resolved "$resolved" \
      --arg sig "$sig_val" \
      --arg label "$label" \
      '. + {state:$state, resolved:$resolved, sig:$sig, label:$label}' <<<"$ref")"
    enriched="$(jq -c --argjson rec "$ref" '. + [$rec]' <<<"$enriched")"
  done

  local blockers_total blockers_resolved
  blockers_total="$(jq '[.[] | select(.role == "blocker")] | length' <<<"$enriched")"
  blockers_resolved="$(jq '[.[] | select(.role == "blocker" and .resolved)] | length' <<<"$enriched")"

  # seen-sig lookup (skipped in parse-only mode).
  local seen="" seen_set
  seen="$(collect_seen_sigs "$issue" || true)"
  seen_set="$(printf '%s\n' "$seen" | awk -F= 'NF>1 {print $2}' | sort -u)"

  local resolved_only new_resolved comment_body="" warnings_body="" should_comment=false should_warn=false
  resolved_only="$(jq -c '[.[] | select(.resolved)]' <<<"$enriched")"
  new_resolved="$(jq -c --arg seen "$seen_set" '
    [.[] | select((.sig // "") as $s | ($seen | split("\n") | index($s)) | not)]
  ' <<<"$resolved_only")"
  local new_count
  new_count="$(jq 'length' <<<"$new_resolved")"
  local ts
  ts="$(utc_now)"
  if [[ $new_count -gt 0 ]]; then
    comment_body="$(compose_digest_body "$ts" "$new_resolved" "$blockers_total" "$blockers_resolved")"
    should_comment=true
  fi

  local warn_count
  warn_count="$(jq 'length' <<<"$warnings_json")"
  if [[ $warn_count -gt 0 ]]; then
    local warn_sig
    warn_sig="$(jq -r '.[]' <<<"$warnings_json" | sort | sig "$(cat)")"
    if ! grep -q "sig=$warn_sig" <<<"$seen"; then
      warnings_body="$(compose_warning_body "$ts" "$warnings_json")"
      should_warn=true
    fi
  fi

  local would_transition=false
  if [[ $blockers_total -gt 0 && $blockers_total -eq $blockers_resolved ]]; then
    would_transition=true
  fi

  # side effects (skipped in parse-only mode).
  if ! is_parse_only; then
    if [[ $should_comment == true ]]; then
      emit_comment "$issue" "$comment_body" digest
    fi
    if [[ $should_warn == true ]]; then
      emit_comment "$issue" "$warnings_body" parse-warning
    fi
    if [[ $would_transition == true ]]; then
      transition_label "$issue"
    fi
  fi

  local issue_arg
  if [[ -n $issue ]]; then
    issue_arg="$issue"
  else
    issue_arg=null
  fi
  jq -cn \
    --argjson issue "$issue_arg" \
    --argjson refs "$enriched" \
    --argjson warnings "$warnings_json" \
    --arg comment "$comment_body" \
    --arg warning "$warnings_body" \
    --arg ts "$ts" \
    --argjson should_comment "$should_comment" \
    --argjson should_warn "$should_warn" \
    --argjson would_transition "$would_transition" \
    --argjson blockers_total "$blockers_total" \
    --argjson blockers_resolved "$blockers_resolved" \
    '{
      issue:$issue,
      timestamp:$ts,
      refs:$refs,
      warnings:$warnings,
      blockers_total:$blockers_total,
      blockers_resolved:$blockers_resolved,
      would_comment:$should_comment,
      would_warn:$should_warn,
      would_transition_label:$would_transition,
      comment_body: (if $comment == "" then null else $comment end),
      warnings_body: (if $warning == "" then null else $warning end)
    }'
}

resolve_target_issues() {
  local explicit="${1:-}"
  if [[ -n $explicit ]]; then
    printf '%s\n' "$explicit"
    return 0
  fi
  gh issue list --state open --label "$BLOCKED_LABEL" --limit 200 \
    --json number --jq '.[].number'
}

# ----- entry point ------------------------------------------------------------

main() {
  local explicit="${1:-}"

  if is_parse_only; then
    export UPSTREAM_TRACKER_OFFLINE_STRICT=1
    local body
    body="$(cat)"
    process_issue_body "" "$body"
    return 0
  fi

  have_cmd gh || die "gh CLI is required"
  have_cmd jq || die "jq is required"

  local issues
  issues="$(resolve_target_issues "$explicit")"
  if [[ -z $issues ]]; then
    log "no issues match label $BLOCKED_LABEL"
    return 0
  fi

  local issue body
  while IFS= read -r issue; do
    [[ -z $issue ]] && continue
    body="$(gh issue view "$issue" --json body --jq '.body')"
    process_issue_body "$issue" "$body" >/dev/null
  done <<<"$issues"
}

main "$@"
