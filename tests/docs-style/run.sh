#!/usr/bin/env bash
# shellcheck shell=bash
# Covers the docs-style pre-commit hook in modules/meta/hooks/docs-style.nix:
# the line cap, the banned-phrase scan and what it must not see (fences, code
# spans, link destinations, URLs), link resolution, and the backticked-path
# check. Most cases here are a false positive or a false negative the hook has
# already had once; without the suite each one returns silently on the next
# edit to the awk that guards it.
#
# The subject is a package rather than a script in the tree, so it is taken
# from PATH, where the dev shell and the script-tests check both put it, or
# from HOOK_DOCS_STYLE. It finds its repository with git rev-parse and reads
# docs/technical-writing/banned-phrases.txt from that root, so every case runs
# inside a fixture repository of its own.
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_PHRASES="${SCRIPT_DIR}/../../docs/technical-writing/banned-phrases.txt"
SUT="${HOOK_DOCS_STYLE:-$(command -v hook-docs-style || true)}"

if [[ -z ${SUT} || ! -x ${SUT} ]]; then
  printf 'run.sh: hook-docs-style is not on PATH; enter the dev shell or set HOOK_DOCS_STYLE\n' >&2
  exit 2
fi
if [[ ! -f ${REAL_PHRASES} ]]; then
  printf 'run.sh: phrase list not found at %s\n' "${REAL_PHRASES}" >&2
  exit 2
fi

tmpdir="$(mktemp -d)"
cleanup() {
  if [[ -d ${tmpdir} ]]; then
    rm -r "${tmpdir}"
  fi
}
trap cleanup EXIT

# Isolate from the operator's real environment and git configuration.
export HOME="${tmpdir}/home"
mkdir -p "${HOME}"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_TERMINAL_PROMPT=0

tests_passed=0
tests_ran=()

pass() {
  tests_passed=$((tests_passed + 1))
  # The caller's name, so the tail of this file can assert that every case
  # defined here actually ran rather than trusting the invocation list.
  tests_ran+=("${FUNCNAME[1]}")
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  if [[ -n ${2:-} && -f ${2:-} ]]; then
    printf '%s\n' '--- hook stderr ---' >&2
    cat "$2" >&2
    printf '%s\n' '-------------------' >&2
  fi
  exit 1
}

# A repository carrying a fixture phrase list: one phrase plus the ISO date
# pattern, so an edit to the committed list cannot move a mechanics case.
# The committed list has its own case at the end.
make_repo() {
  local repo="${tmpdir}/$1"

  mkdir -p "${repo}/docs/technical-writing"
  git init -q -b main "${repo}"
  cat >"${repo}/docs/technical-writing/banned-phrases.txt" <<'LIST'
# fixture list
\bfixture-phrase\b
\b20[0-9]{2}-[01][0-9]-[0-3][0-9]\b
LIST
  printf '%s\n' "${repo}"
}

# Writes a page from stdin, creating its directory on the way.
write_page() {
  local repo="$1"
  local path="$2"

  mkdir -p "$(dirname "${repo}/${path}")"
  cat >"${repo}/${path}"
}

# Writes a page of exactly $2 lines, creating its directory on the way; with a
# third argument the last line has no newline.
write_lines() {
  local path="$1"
  local count="$2"
  local unterminated="${3:-}"
  local i

  mkdir -p "$(dirname "${path}")"
  {
    for ((i = 1; i < count; i++)); do
      printf 'line %d\n' "${i}"
    done
    if [[ -n ${unterminated} ]]; then
      printf 'line %d' "${count}"
    else
      printf 'line %d\n' "${count}"
    fi
  } >"${path}"
}

# Runs the hook from the fixture root with root-relative paths, the way
# pre-commit invokes it, with every fixture file staged first: link and path
# targets resolve against the index, so an unstaged fixture reads as missing.
run_hook() {
  local repo="$1"
  shift
  git -C "${repo}" add -A
  run_hook_unstaged "${repo}" "$@"
}

run_hook_unstaged() {
  local repo="$1"
  shift
  hook_rc=0
  (cd "${repo}" && "${SUT}" "$@") >"${tmpdir}/hook.out" 2>"${tmpdir}/hook.err" || hook_rc=$?
}

assert_rc() {
  local want="$1"
  local label="$2"
  [[ ${hook_rc} -eq ${want} ]] || fail "${label}: expected rc ${want}, got ${hook_rc}" "${tmpdir}/hook.err"
}

assert_err_has() {
  local want="$1"
  local label="$2"
  grep -q -F -- "${want}" "${tmpdir}/hook.err" ||
    fail "${label}: stderr lacks [${want}]" "${tmpdir}/hook.err"
}

assert_err_lacks() {
  local unwanted="$1"
  local label="$2"
  ! grep -q -F -- "${unwanted}" "${tmpdir}/hook.err" ||
    fail "${label}: stderr carries [${unwanted}]" "${tmpdir}/hook.err"
}

# A passing run is silent: pre-commit shows the hook's output only on
# failure, so anything written on success would never be read.
assert_clean() {
  local label="$1"
  assert_rc 0 "${label}"
  [[ ! -s ${tmpdir}/hook.err ]] || fail "${label}: a passing run wrote to stderr" "${tmpdir}/hook.err"
  [[ ! -s ${tmpdir}/hook.out ]] || fail "${label}: a passing run wrote to stdout" "${tmpdir}/hook.out"
}

assert_violations() {
  local count="$1"
  local label="$2"
  assert_rc 1 "${label}"
  assert_err_has "docs-style: ${count} violation(s)" "${label}"
}

# --- arguments -------------------------------------------------------------

test_no_arguments_exits_zero() {
  local repo
  repo="$(make_repo no-args)"

  run_hook "${repo}"
  assert_clean "no arguments"
  pass
}

# pre-commit only passes root-relative paths that exist, but the hook is also
# on the dev shell PATH and cds to the root before reading its arguments, so a
# typo or a path typed from a subdirectory checked nothing and reported success.
test_an_argument_that_is_not_a_file_is_a_violation() {
  local repo
  repo="$(make_repo not-a-file)"
  mkdir -p "${repo}/docs/guides"

  # pre-commit's own flag spelling, typed by hand, is an argument that starts
  # with a dash; realpath read it as an option and died before the report.
  run_hook "${repo}" docs/missing.md docs/guides tests/typo.md --files
  assert_violations 4 "not a file"
  assert_err_has "docs-style: not a file: docs/missing.md" "missing file"
  assert_err_has "docs-style: not a file: docs/guides" "directory"
  # The file check runs ahead of the exemption, so a typo under an exempt
  # prefix is loud as well.
  assert_err_has "docs-style: not a file: tests/typo.md" "exempt prefix"
  assert_err_has "docs-style: not a file: --files" "dash argument"
  pass
}

test_a_page_whose_name_starts_with_a_dash_is_checked() {
  local repo
  repo="$(make_repo dash-name)"
  write_lines "${repo}/docs/-page.md" 151

  run_hook "${repo}" docs/-page.md
  assert_violations 1 "dash name"
  assert_err_has "docs/-page.md: 151 lines exceeds the 150 line cap" "dash name"
  pass
}

# --- exempt paths ----------------------------------------------------------

# The match lives in the hook rather than in a pre-commit exclude so it can be
# pinned here: an anchor lost from a pattern, or a prefix widened, shows up as
# a page skipped when it should be checked or checked when it should be
# skipped. Each fixture is over the cap, so being checked is visible.

# Only the root README.md is generated; the ones under docs/ are hand-written
# index pages, and a basename match once exempted all of them.
test_the_generated_root_readme_is_exempt_and_the_docs_readmes_are_not() {
  local repo
  repo="$(make_repo readme)"
  write_lines "${repo}/README.md" 151
  write_lines "${repo}/docs/README.md" 151
  write_lines "${repo}/docs/architecture/README.md" 151

  run_hook "${repo}" README.md
  assert_clean "root README"

  run_hook "${repo}" docs/README.md docs/architecture/README.md
  assert_violations 2 "docs READMEs"
  pass
}

test_agent_instruction_files_are_exempt_by_exact_name() {
  local repo
  repo="$(make_repo agent-files)"
  write_lines "${repo}/CLAUDE.md" 151
  write_lines "${repo}/AGENTS.md" 151
  write_lines "${repo}/docs/AGENTS.md" 151
  write_lines "${repo}/docs/claude-code/CLAUDE.md" 151
  write_lines "${repo}/docs/claude-code/writing-CLAUDE.md" 151

  run_hook "${repo}" CLAUDE.md AGENTS.md docs/AGENTS.md docs/claude-code/CLAUDE.md
  assert_clean "instruction files"

  run_hook "${repo}" docs/claude-code/writing-CLAUDE.md
  assert_violations 1 "a page named after one"
  pass
}

# docs/nixos-manual/ is also under the repo-wide pre-commit exclude; it is
# matched here as well so a hand run on a mirrored manual page stays quiet.
test_drafts_the_manual_and_test_fixtures_are_exempt_by_directory() {
  local repo
  repo="$(make_repo drafts)"
  write_lines "${repo}/docs/drafts/plan.md" 151
  write_lines "${repo}/docs/drafts/nested/plan.md" 151
  write_lines "${repo}/docs/nixos-manual/release-notes/rl-2405.section.md" 151
  write_lines "${repo}/tests/suite/fixture.md" 151
  write_lines "${repo}/docs/drafts.md" 151

  run_hook "${repo}" docs/drafts/plan.md docs/drafts/nested/plan.md \
    docs/nixos-manual/release-notes/rl-2405.section.md tests/suite/fixture.md
  assert_clean "exempt directories"

  run_hook "${repo}" docs/drafts.md
  assert_violations 1 "a page beside the directory"
  pass
}

# `find . -name '*.md' | xargs hook-docs-style` hands the hook ./-prefixed
# paths, and the cd to the root opens docs/./index.md and an absolute path
# just the same; the raw string once had to match the exemption exactly.
test_an_exempt_path_is_matched_however_it_is_spelled() {
  local repo
  repo="$(make_repo spellings)"
  write_lines "${repo}/README.md" 151
  write_lines "${repo}/docs/index.md" 151
  write_lines "${repo}/docs/nixos-manual/page.md" 151
  write_lines "${repo}/docs/drafts/plan.md" 151
  write_lines "${repo}/docs/page.md" 151

  run_hook "${repo}" ./README.md docs/../README.md docs/./index.md \
    ./docs/nixos-manual/page.md "${repo}/docs/drafts/plan.md"
  assert_clean "exempt spellings"

  run_hook "${repo}" ./docs/page.md
  assert_violations 1 "a checked page spelled with ./"
  assert_err_has "docs/page.md: 151 lines exceeds the 150 line cap" "canonical path in the report"
  pass
}

test_a_clean_page_passes() {
  local repo
  repo="$(make_repo clean)"
  : >"${repo}/docs/other.md"
  write_page "${repo}" docs/page.md <<'PAGE'
# Page

Prose with a [link](other.md) and the path `docs/other.md`.
PAGE

  run_hook "${repo}" docs/page.md
  assert_clean "clean page"
  pass
}

# --- the line cap ----------------------------------------------------------

test_the_line_cap_is_150() {
  local repo
  repo="$(make_repo cap)"
  write_lines "${repo}/docs/at-cap.md" 150
  write_lines "${repo}/docs/over-cap.md" 151

  run_hook "${repo}" docs/at-cap.md
  assert_clean "150 lines"

  run_hook "${repo}" docs/over-cap.md
  assert_violations 1 "151 lines"
  assert_err_has "docs/over-cap.md: 151 lines exceeds the 150 line cap" "151 lines"
  pass
}

# wc -l counts newlines, so a 151-line page whose last line has none read as
# 150 and passed.
test_the_line_cap_counts_an_unterminated_last_line() {
  local repo
  repo="$(make_repo cap-unterminated)"
  write_lines "${repo}/docs/over-cap.md" 151 unterminated

  run_hook "${repo}" docs/over-cap.md
  assert_violations 1 "unterminated last line"
  assert_err_has "151 lines exceeds the 150 line cap" "unterminated last line"
  pass
}

# The table of contents grows with every page, so only the cap skips it. A
# whole-file exclude would take the one page that is mostly links out of the
# link check.
test_the_index_skips_the_cap_only() {
  local repo
  repo="$(make_repo index)"
  write_lines "${repo}/docs/index.md" 151

  run_hook "${repo}" docs/index.md
  assert_clean "index over the cap"

  write_page "${repo}" docs/index.md <<'PAGE'
# Index

- [gone](missing.md)
- fixture-phrase in a summary
PAGE
  run_hook "${repo}" docs/index.md
  assert_violations 2 "index phrases and links"
  assert_err_has "docs/index.md:3: relative link target does not resolve: missing.md" "index link"
  assert_err_has "docs/index.md:4: - fixture-phrase in a summary" "index phrase"
  pass
}

# --- the banned-phrase scan ------------------------------------------------

test_a_banned_phrase_in_prose_fails() {
  local repo
  repo="$(make_repo phrase)"
  write_page "${repo}" docs/page.md <<'PAGE'
# Page

Prose.
Prose with FIXTURE-PHRASE in it.
PAGE

  run_hook "${repo}" docs/page.md
  assert_violations 1 "phrase"
  assert_err_has "docs/page.md:4: Prose with FIXTURE-PHRASE in it." "phrase line"
  pass
}

# Line numbers are reported against the file, so the blanking passes keep
# every line in place rather than dropping the ones they clear. A closing run
# must be at least as long as the opening one, so a longer fence can wrap a
# shorter one shown as an example.
test_a_phrase_inside_a_fence_is_ignored() {
  local repo
  repo="$(make_repo fence)"
  write_page "${repo}" docs/page.md <<'PAGE'
# Page

```sh
echo fixture-phrase
```

~~~
fixture-phrase
~~~

  ```
  fixture-phrase indented
  ```

````md
```
fixture-phrase inside a shorter fence shown as an example
```
````

fixture-phrase after the fences close.
PAGE

  run_hook "${repo}" docs/page.md
  assert_violations 1 "fences"
  assert_err_has "docs/page.md:21: fixture-phrase after the fences close." "line after the fences"
  pass
}

# The > marker sits ahead of the fence on every quoted line, so the fence was
# never recognized and a quoted listing reached every scan as prose. A fenced
# block is never lazily continued, so a quoted fence also ends with its
# quote, and the prose after it is scanned rather than swallowed.
test_a_fence_inside_a_blockquote_is_ignored() {
  local repo
  repo="$(make_repo quoted-fence)"
  write_page "${repo}" docs/page.md <<'PAGE'
# Page

> ```sh
> fixture-phrase inside a quoted fence
> [text](missing.md) and `docs/missing.md`
> ```

> > ~~~
> > fixture-phrase two levels down
> > ~~~

> ```
> fixture-phrase in a quoted fence that ends with its quote
fixture-phrase in prose right after the quote.
PAGE

  run_hook "${repo}" docs/page.md
  assert_violations 1 "quoted fences"
  assert_err_has "docs/page.md:14: fixture-phrase in prose right after the quote." "prose after the quote"
  pass
}

# A span closes only on a backtick run of its opening length (CommonMark), so
# a double run is one span, a single backtick inside it is text, and an
# unmatched run is literal. Toggling on every backtick left the second and
# third shapes in prose.
test_a_phrase_inside_a_code_span_is_ignored() {
  local repo
  repo="$(make_repo code-span)"
  write_page "${repo}" docs/page.md <<'PAGE'
# Page

Single `fixture-phrase` span.
Double ``fixture-phrase`` span.
Double ``a ` fixture-phrase`` span holding a backtick.
Two `spans` on `fixture-phrase` one line.
Unmatched ` run then fixture-phrase in prose.
A `span` beside fixture-phrase in prose.
PAGE

  run_hook "${repo}" docs/page.md
  assert_violations 2 "code spans"
  assert_err_has 'docs/page.md:7: Unmatched ` run then fixture-phrase in prose.' "unmatched run"
  # The report prints the source line, span intact, rather than the stripped
  # text the pattern matched, so the reader can find it in the file.
  # shellcheck disable=SC2016 # a literal pair of backticks, not a substitution
  assert_err_has 'docs/page.md:8: A `span` beside fixture-phrase in prose.' "source line"
  pass
}

# Only the destination is blanked: link text stays in the scan, and so does
# the prose of a footnote definition, which once matched the
# reference-definition rule and lost everything after its label.
test_link_destinations_and_urls_are_not_scanned() {
  local repo
  repo="$(make_repo link-targets)"
  : >"${repo}/docs/2024-03-11.md"
  write_page "${repo}" docs/page.md <<'PAGE'
# Page

An [inline link](2024-03-11.md) and a [reference link][post].
An autolink <https://example.com/2024-03-11> and a bare https://example.com/t/2024-03-11-x URL.
A footnote.[^1]

[post]: 2024-03-11.md
[^1]: The footnote prose holds fixture-phrase.
PAGE

  run_hook "${repo}" docs/page.md
  assert_violations 1 "link destinations"
  assert_err_has "docs/page.md:8: [^1]: The footnote prose holds fixture-phrase." "footnote prose"
  pass
}

test_link_text_is_scanned() {
  local repo
  repo="$(make_repo link-text)"
  : >"${repo}/docs/other.md"
  write_page "${repo}" docs/page.md <<'PAGE'
# Page

A [fixture-phrase link](other.md).
PAGE

  run_hook "${repo}" docs/page.md
  assert_violations 1 "link text"
  assert_err_has "docs/page.md:3: A [fixture-phrase link](other.md)." "link text"
  pass
}

# --- link resolution -------------------------------------------------------

test_a_dead_relative_link_fails() {
  local repo
  repo="$(make_repo dead-link)"
  : >"${repo}/docs/other.md"
  write_page "${repo}" docs/guides/page.md <<'PAGE'
# Page

A [sibling](../other.md), a [dead one](missing.md), and a [dead reference][ref].

[ref]: also-missing.md
PAGE

  run_hook "${repo}" docs/guides/page.md
  assert_violations 2 "dead links"
  assert_err_has "docs/guides/page.md:3: relative link target does not resolve: missing.md" "inline"
  assert_err_has "docs/guides/page.md:5: relative link target does not resolve: also-missing.md" "reference"
  pass
}

test_an_absolute_target_resolves_from_the_root() {
  local repo
  repo="$(make_repo absolute)"
  : >"${repo}/docs/other.md"
  write_page "${repo}" docs/guides/page.md <<'PAGE'
# Page

A [root link](/docs/other.md), the [root itself](/), and a [dead root link](/docs/missing.md).
PAGE

  run_hook "${repo}" docs/guides/page.md
  assert_violations 1 "absolute"
  assert_err_has "does not resolve: /docs/missing.md" "absolute dead"
  assert_err_lacks "/docs/other.md" "absolute live"
  pass
}

# A trailing title, a <...> wrapper, a #fragment and padding inside the
# parentheses are all CommonMark, and each reached the filesystem as part of
# the path once.
test_a_destination_is_normalized_before_resolving() {
  local repo
  repo="$(make_repo normalize)"
  : >"${repo}/docs/other.md"
  : >"${repo}/docs/two words.md"
  write_page "${repo}" docs/page.md <<'PAGE'
# Page

[fragment only](#section), [with fragment](other.md#section),
[titled](other.md "Other"), [single quoted](other.md 'Other'),
[wrapped](<two words.md>), [wrapped and titled](<two words.md> "Two"),
[padded](  other.md  ).
PAGE

  run_hook "${repo}" docs/page.md
  assert_clean "normalized destinations"
  pass
}

# A relative reference cannot begin with scheme: (RFC 3986 section 4.2), so
# the skip matches the scheme grammar rather than a list and ignores case;
# //host and #fragment are the two other non-path shapes.
test_scheme_targets_are_skipped() {
  local repo
  repo="$(make_repo schemes)"
  write_page "${repo}" docs/page.md <<'PAGE'
# Page

[a](https://example.com/x), [b](HTTPS://example.com/x), [c](mailto:a@example.com),
[d](git://example.com/repo), [e](file:///var/lib/x), [f](//cdn.example.com/x),
[g](matrix:r/room), [h](data:text/plain,hi).

[i]: ssh://git@example.com/repo
PAGE

  run_hook "${repo}" docs/page.md
  assert_clean "schemes"
  pass
}

# pre-commit stashes unstaged changes to tracked files only, so a target that
# exists on disk but was never staged is still there while the hook runs;
# resolving against the working tree let the commit land with a link no
# commit satisfies. The message names the cause, since the fix is git add.
test_an_untracked_target_does_not_resolve() {
  local repo
  repo="$(make_repo untracked)"
  : >"${repo}/docs/new.md"
  write_page "${repo}" docs/page.md <<'PAGE'
# Page

A [new page](new.md), also as `docs/new.md`, and a [gone one](missing.md).
PAGE

  run_hook_unstaged "${repo}" docs/page.md
  assert_violations 3 "untracked target"
  assert_err_has "docs/page.md:3: relative link target is not tracked by git: new.md" "untracked link"
  assert_err_has "docs/page.md:3: backticked path is not tracked by git: docs/new.md" "untracked path"
  assert_err_has "docs/page.md:3: relative link target does not resolve: missing.md" "absent link"

  git -C "${repo}" add docs/new.md
  run_hook_unstaged "${repo}" docs/page.md
  assert_violations 1 "staged target"
  assert_err_lacks "new.md" "staged target"
  pass
}

# Markup quoted in a code span or a fence is an example, not a link.
test_link_syntax_inside_code_is_not_a_link() {
  local repo
  repo="$(make_repo link-in-code)"
  write_page "${repo}" docs/page.md <<'PAGE'
# Page

Write a link as `[text](missing.md)`.

```md
[text](also-missing.md)
```
PAGE

  run_hook "${repo}" docs/page.md
  assert_clean "link syntax in code"
  pass
}

# --- backticked paths ------------------------------------------------------

# Every prefix the check claims, so a prefix dropped from the allowlist fails
# here: a span is a repository path only when it starts with one of these.
test_a_dead_backticked_path_fails_under_every_claimed_prefix() {
  local repo
  repo="$(make_repo backticked)"
  mkdir -p "${repo}/modules"
  : >"${repo}/modules/present.nix"
  write_page "${repo}" docs/page.md <<'PAGE'
# Page

`modules/present.nix` exists; `modules/missing.nix` does not.
`docs/missing.md` `scripts/missing.sh` `packages/missing.nix` `tests/missing/run.sh`
`lib/missing.nix` `.github/workflows/missing.yml` `flake.nix` `build.sh`
PAGE

  run_hook "${repo}" docs/page.md
  assert_violations 9 "claimed prefixes"
  assert_err_has "docs/page.md:3: backticked path does not exist: modules/missing.nix" "modules"
  assert_err_has "does not exist: .github/workflows/missing.yml" ".github"
  assert_err_has "does not exist: flake.nix" "flake.nix"
  assert_err_has "does not exist: build.sh" "build.sh"
  assert_err_lacks "modules/present.nix" "existing path"
  pass
}

test_a_backticked_path_drops_its_line_fragment_and_slash_suffix() {
  local repo
  repo="$(make_repo suffixes)"
  : >"${repo}/docs/other.md"
  write_page "${repo}" docs/page.md <<'PAGE'
# Page

`docs/other.md:12`, `docs/other.md:12-20`, `docs/other.md#section`, `docs/`.
PAGE

  run_hook "${repo}" docs/page.md
  assert_clean "suffixes"
  pass
}

# A glob, a <placeholder>, braces, a variable, a question mark or whitespace
# make the span templated prose rather than one path.
test_a_templated_span_is_not_a_path() {
  local repo
  repo="$(make_repo templated)"
  write_page "${repo}" docs/page.md <<'PAGE'
# Page

`modules/*.nix`, `docs/<host>/index.md`, `docs/{a,b}.md`, `scripts/$name.sh`,
`docs/two words.md`, `modules/x.nix?`.
PAGE

  run_hook "${repo}" docs/page.md
  assert_clean "templated spans"
  pass
}

# secrets/ is a gitlink, absent in a clone without submodule init, so it is
# deliberately not a claimed prefix; a fenced path is a listing, not a claim.
test_a_span_outside_the_prefixes_is_not_a_path() {
  local repo
  repo="$(make_repo unclaimed)"
  write_page "${repo}" docs/page.md <<'PAGE'
# Page

`src/main.c`, `nixos-rebuild switch`, `secrets/missing.yaml`, `/etc/nixos/configuration.nix`.

```
modules/missing.nix
```
PAGE

  run_hook "${repo}" docs/page.md
  assert_clean "unclaimed spans"
  pass
}

# --- the run ---------------------------------------------------------------

test_violations_are_counted_across_files() {
  local repo
  repo="$(make_repo counted)"
  write_page "${repo}" docs/one.md <<'PAGE'
# One

fixture-phrase.
PAGE
  write_page "${repo}" docs/two.md <<'PAGE'
# Two

fixture-phrase and a [dead link](missing.md).
PAGE

  run_hook "${repo}" docs/one.md docs/two.md
  assert_violations 3 "counted"
  assert_err_has "docs/one.md:3:" "first file"
  assert_err_has "docs/two.md:3:" "second file"
  pass
}

# The list is read at run time so it can grow without a rebuild, which also
# means a pattern grep -E rejects is only met when the hook runs: that aborts
# with grep's status rather than passing as no match.
test_a_pattern_grep_rejects_aborts_the_run() {
  local repo
  repo="$(make_repo broken-pattern)"
  printf '%s\n' '\b(unclosed' >"${repo}/docs/technical-writing/banned-phrases.txt"
  write_page "${repo}" docs/page.md <<'PAGE'
# Page

Prose.
PAGE

  run_hook "${repo}" docs/page.md
  assert_rc 2 "broken pattern"
  assert_err_has "docs-style: grep failed (exit 2)" "broken pattern"
  assert_err_lacks "violation(s)" "broken pattern"
  pass
}

# The committed list, so a pattern added there that grep -E rejects fails
# here rather than on the next commit, and the ISO date rule the style guide
# leads with keeps matching.
test_the_committed_phrase_list_parses_and_catches_a_date() {
  local repo
  repo="$(make_repo committed-list)"
  cp "${REAL_PHRASES}" "${repo}/docs/technical-writing/banned-phrases.txt"
  write_page "${repo}" docs/page.md <<'PAGE'
# Page

Prose without a phrase, sourced from https://example.com/2026-01-01-post.
PAGE

  run_hook "${repo}" docs/page.md
  assert_clean "committed list, clean page"

  write_page "${repo}" docs/page.md <<'PAGE'
# Page

Switched in on 2026-01-01.
PAGE
  run_hook "${repo}" docs/page.md
  assert_violations 1 "committed list, date"
  assert_err_has "docs/page.md:3: Switched in on 2026-01-01." "committed list, date"
  pass
}

test_no_arguments_exits_zero
test_an_argument_that_is_not_a_file_is_a_violation
test_a_page_whose_name_starts_with_a_dash_is_checked
test_the_generated_root_readme_is_exempt_and_the_docs_readmes_are_not
test_agent_instruction_files_are_exempt_by_exact_name
test_drafts_the_manual_and_test_fixtures_are_exempt_by_directory
test_an_exempt_path_is_matched_however_it_is_spelled
test_a_clean_page_passes
test_the_line_cap_is_150
test_the_line_cap_counts_an_unterminated_last_line
test_the_index_skips_the_cap_only
test_a_banned_phrase_in_prose_fails
test_a_phrase_inside_a_fence_is_ignored
test_a_fence_inside_a_blockquote_is_ignored
test_a_phrase_inside_a_code_span_is_ignored
test_link_destinations_and_urls_are_not_scanned
test_link_text_is_scanned
test_a_dead_relative_link_fails
test_an_absolute_target_resolves_from_the_root
test_a_destination_is_normalized_before_resolving
test_scheme_targets_are_skipped
test_an_untracked_target_does_not_resolve
test_link_syntax_inside_code_is_not_a_link
test_a_dead_backticked_path_fails_under_every_claimed_prefix
test_a_backticked_path_drops_its_line_fragment_and_slash_suffix
test_a_templated_span_is_not_a_path
test_a_span_outside_the_prefixes_is_not_a_path
test_violations_are_counted_across_files
test_a_pattern_grep_rejects_aborts_the_run
test_the_committed_phrase_list_parses_and_catches_a_date

# Asserted, not merely reported, for the reason tests/secrets-guard/run.sh
# states at the same place: the invocation list is hand-maintained, so a dropped
# line would cut coverage while the suite still exits 0 and prints a smaller
# number that nothing compares against.
missing=()
while IFS= read -r line; do
  fn="${line##* }"
  [[ ${fn} == test_* ]] || continue
  ran=0
  for name in "${tests_ran[@]}"; do
    if [[ ${name} == "${fn}" ]]; then
      ran=1
      break
    fi
  done
  [[ ${ran} -eq 1 ]] || missing+=("${fn}")
done < <(declare -F)

if [[ ${#missing[@]} -gt 0 ]]; then
  printf 'run.sh: defined but never reached pass: %s\n' "${missing[*]}" >&2
  printf 'run.sh: add it to the invocation list above, or delete it.\n' >&2
  exit 1
fi

printf '%d passed\n' "${tests_passed}"
