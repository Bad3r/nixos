#!/usr/bin/env bash
# Cache-coverage report for host closures (issue #381).
#
# Detects configuration changes that silently convert substitutable store
# paths into local source builds (overlay edits, overrideAttrs on shared
# libraries, stylix targets). Evaluation and HTTP narinfo probes only: this
# script never builds anything.
#
# Method, per host: instantiate the system toplevel derivation, then walk
# the derivation graph top down. For every derivation, probe the configured
# substituters (plus cache.nixos.org) for its output paths over HTTP. A
# derivation whose outputs are all served terminates the walk: binary
# caches are closed under references, so everything below it substitutes
# too. An unserved derivation would build locally on a fresh machine; the
# walk descends into its inputDrvs. Unlike `nix build --dry-run`, the walk
# ignores local store validity, so leftover store paths from earlier
# generations cannot mask a regression, and the daemon narinfo negative
# cache (narinfo-cache-negative-ttl) is bypassed.
#
# Each would-build derivation lands in one class:
#   unexpected-local   the same attribute in the raw nixpkgs input (no
#                      overlays) yields an outPath that cache.nixos.org
#                      serves: an overlay or override broke cache coverage
#                      (FAIL)
#   allowlisted        unexpected-local but accepted in the allowlist
#   diverged-uncached  diverged from stock, but stock is not served either
#   uncached-stock     identical to stock, not yet published by hydra
#   fetch              fixed-output derivation (source download)
#   local-only         no stock nixpkgs counterpart (config texts, units,
#                      wrappers, custom packages, foreign-system builds)
#
# Exit codes: 0 ok, 1 unexpected-local over threshold, 2 usage or
# environment error.
set -Eeu -o pipefail

FLAKE_DIR=""
HOSTS=()
ALLOWLIST=""
MAX_COUNT=0
MAX_SIZE=0
VERBOSE=false
CURL_MAX_TIME=30
CURL_PARALLEL=40
# `nix derivation show` receives the whole walk frontier as argv. A
# low-level divergence (an stdenv- or xz-tier override) can make one level
# hold the entire uncached subgraph (tens of thousands of .drv paths), so
# the frontier is chunked to stay under ARG_MAX in exactly that scenario.
DRV_SHOW_BATCH=512
# Superset spelling for pre-cutover CppNix and Lix, mirroring build.sh; the
# unknown-name warning from either implementation is harmless.
EXPERIMENTAL_FEATURES="nix-command flakes pipe-operator pipe-operators flake-self-attrs"

usage() {
  cat <<EOF
Usage: ${0##*/} [OPTIONS]

Report host closure paths that would build locally although stock nixpkgs
publishes a substitutable equivalent. Derivation-graph walk plus narinfo
probes only; nothing is built.

Options:
  -H, --host HOST       Restrict to HOST (repeatable; default: all hosts)
  -p, --flake-dir PATH  Repo root (default: git toplevel, then \$PWD)
      --allowlist FILE  Accepted-divergence globs
                        (default: scripts/cache-coverage-allowlist.txt)
      --max-count N     Allowed unexpected-local entries (default: 0)
      --max-size SIZE   Allowed total stock nar size of unexpected-local
                        entries, bytes or iec like 50M (default: 0)
  -v, --verbose         Also list every substitutable derivation
  -h, --help            Show this help

Exit: 0 within thresholds, 1 over thresholds, 2 usage/environment error.
EOF
}

err() {
  printf 'cache-coverage: error: %s\n' "$1" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  -H | --host)
    [[ -n ${2:-} ]] || {
      err "$1 requires an argument"
      exit 2
    }
    HOSTS+=("$2")
    shift 2
    ;;
  -p | --flake-dir)
    [[ -n ${2:-} ]] || {
      err "$1 requires an argument"
      exit 2
    }
    FLAKE_DIR="$2"
    shift 2
    ;;
  --allowlist)
    [[ -n ${2:-} ]] || {
      err "$1 requires an argument"
      exit 2
    }
    ALLOWLIST="$2"
    shift 2
    ;;
  --max-count)
    [[ -n ${2:-} ]] || {
      err "$1 requires an argument"
      exit 2
    }
    MAX_COUNT="$2"
    shift 2
    ;;
  --max-size)
    [[ -n ${2:-} ]] || {
      err "$1 requires an argument"
      exit 2
    }
    MAX_SIZE="$(numfmt --from=iec -- "$2")" || {
      err "cannot parse --max-size $2"
      exit 2
    }
    shift 2
    ;;
  -v | --verbose)
    VERBOSE=true
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    err "unknown option: $1"
    usage >&2
    exit 2
    ;;
  esac
done

for tool in nix jq curl git numfmt; do
  command -v "$tool" >/dev/null 2>&1 || {
    err "required tool not found: $tool"
    exit 2
  }
done

if [[ -z ${FLAKE_DIR} ]]; then
  FLAKE_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
[[ -f "${FLAKE_DIR}/flake.nix" ]] || {
  err "flake.nix not found in ${FLAKE_DIR}"
  exit 2
}
[[ -f "${FLAKE_DIR}/flake.lock" ]] || {
  err "flake.lock not found in ${FLAKE_DIR}"
  exit 2
}
if [[ -z ${ALLOWLIST} ]]; then
  ALLOWLIST="${FLAKE_DIR}/scripts/cache-coverage-allowlist.txt"
fi

# Linked worktrees cannot be fetched as git+file flakes (.git is a file
# there), and path: also includes a dirty tree, which is exactly what a
# pre-switch report should measure.
FLAKE_REF="path:${FLAKE_DIR}"

TMPDIR_ROOT="$(mktemp -d -t cache-coverage.XXXXXX)"
trap 'rm -rf "${TMPDIR_ROOT}"' EXIT

nix_cmd() {
  nix --extra-experimental-features "${EXPERIMENTAL_FEATURES}" "$@"
}

ALLOW_PATTERNS=()
if [[ -f ${ALLOWLIST} ]]; then
  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line//[[:space:]]/}"
    [[ -n ${line} ]] && ALLOW_PATTERNS+=("${line}")
  done <"${ALLOWLIST}"
fi

allowlisted() {
  local name="$1" pat
  for pat in "${ALLOW_PATTERNS[@]}"; do
    # shellcheck disable=SC2053 # glob match against the pattern is intended
    [[ ${name} == ${pat} ]] && return 0
  done
  return 1
}

# Locked nixpkgs input (root node), the no-overlays comparison baseline.
read_lock() {
  jq -r "$1" "${FLAKE_DIR}/flake.lock"
}
if [[ "$(read_lock '.nodes.root.inputs.nixpkgs | type')" != "string" ]]; then
  err "flake.lock root nixpkgs input is missing or uses a follows path"
  exit 2
fi
NIXPKGS_NODE="$(read_lock '.nodes.root.inputs.nixpkgs')"
NIXPKGS_TYPE="$(read_lock ".nodes[\"${NIXPKGS_NODE}\"].locked.type")"
if [[ ${NIXPKGS_TYPE} != "github" ]]; then
  err "unsupported nixpkgs input type '${NIXPKGS_TYPE}' (github expected)"
  exit 2
fi
NIXPKGS_OWNER="$(read_lock ".nodes[\"${NIXPKGS_NODE}\"].locked.owner")"
NIXPKGS_REPO="$(read_lock ".nodes[\"${NIXPKGS_NODE}\"].locked.repo")"
NIXPKGS_REV="$(read_lock ".nodes[\"${NIXPKGS_NODE}\"].locked.rev")"
NIXPKGS_NARHASH="$(read_lock ".nodes[\"${NIXPKGS_NODE}\"].locked.narHash")"

# hash part = store path basename before the first dash
hash_part() {
  local base="${1##*/}"
  printf '%s' "${base%%-*}"
}

# Substituter base URL usable for narinfo probes; empty for non-HTTP stores.
probe_base() {
  local url="$1"
  url="${url%%\?*}"
  url="${url%/}"
  case "${url}" in
  http://* | https://*) printf '%s' "${url}" ;;
  *) printf '' ;;
  esac
}

# PROBE[url] = http code; shared across hosts so common paths are probed
# once. probe_urls FILE probes every url in FILE that is not cached yet,
# one curl process per batch with parallel transfers.
declare -A PROBE=()
PROBE_ERRORS=0
probe_urls() {
  local list="$1" cfg="${TMPDIR_ROOT}/curl.cfg" out="${TMPDIR_ROOT}/curl.out"
  local url code n=0
  : >"${cfg}"
  while IFS= read -r url; do
    [[ -z ${url} || -n ${PROBE[${url}]:-} ]] && continue
    PROBE["${url}"]="pending"
    printf 'url = "%s"\noutput = "/dev/null"\n' "${url}" >>"${cfg}"
    n=$((n + 1))
  done <"${list}"
  [[ ${n} -eq 0 ]] && return 0
  curl --parallel --parallel-max "${CURL_PARALLEL}" --silent \
    --max-time "${CURL_MAX_TIME}" --retry 2 \
    --write-out '%{http_code} %{url}\n' \
    --config "${cfg}" >"${out}" 2>/dev/null || true
  while read -r code url; do
    [[ -z ${url} ]] && continue
    PROBE["${url}"]="${code}"
  done <"${out}"
  # Transfers curl never reported (DNS failure, abort) stay pending.
  for url in "${!PROBE[@]}"; do
    if [[ ${PROBE[${url}]} == "pending" ]]; then
      PROBE["${url}"]="000"
    fi
  done
  PROBE_ERRORS=0
  for url in "${!PROBE[@]}"; do
    if [[ ${PROBE[${url}]} == "000" ]]; then
      PROBE_ERRORS=$((PROBE_ERRORS + 1))
    fi
  done
}

# fetch_narsize URL: print NarSize of a narinfo, empty when unavailable.
fetch_narsize() {
  local url="$1" body="${TMPDIR_ROOT}/narinfo.body"
  if curl --silent --max-time "${CURL_MAX_TIME}" --retry 2 \
    --output "${body}" "${url}" 2>/dev/null; then
    awk '/^NarSize: / { print $2; exit }' "${body}"
  fi
  rm -f "${body}"
}

human() {
  if [[ -n ${1:-} ]]; then
    numfmt --to=iec -- "$1"
  else
    printf '?'
  fi
}

print_group() {
  local title="$1" note="$2" count="$3"
  shift 3
  printf '  %s (%s)%s\n' "${title}" "${count}" "${note:+  [${note}]}"
  local e
  for e in "$@"; do
    printf '    %s\n' "${e}"
  done
}

if [[ ${#HOSTS[@]} -eq 0 ]]; then
  mapfile -t HOSTS < <(nix_cmd eval "${FLAKE_REF}#nixosConfigurations" \
    --accept-flake-config --json --apply builtins.attrNames | jq -r '.[]')
fi
[[ ${#HOSTS[@]} -gt 0 ]] || {
  err "no hosts found"
  exit 2
}

printf 'cache-coverage report\n'
printf 'flake: %s\n' "${FLAKE_REF}"
printf 'stock baseline: github:%s/%s/%s (no overlays, allowUnfree)\n' \
  "${NIXPKGS_OWNER}" "${NIXPKGS_REPO}" "${NIXPKGS_REV:0:12}"
printf 'thresholds: max unexpected count %s, max unexpected nar size %s\n' \
  "${MAX_COUNT}" "$(human "${MAX_SIZE}")"

TOTAL_UNEXPECTED=0
TOTAL_UNEXPECTED_SIZE=0

for host in "${HOSTS[@]}"; do
  printf '\n== %s ==\n' "${host}"
  tmp="${TMPDIR_ROOT}/${host}"
  mkdir -p "${tmp}"

  installable="${FLAKE_REF}#nixosConfigurations.${host}.config.system.build.toplevel"
  if ! toplevel_drv="$(nix_cmd path-info --derivation "${installable}" \
    --accept-flake-config 2>"${tmp}/eval.log")"; then
    err "evaluation failed for ${host}"
    tail -n 20 "${tmp}/eval.log" >&2
    exit 2
  fi

  # A fresh machine substitutes from substituters plus extra-substituters;
  # app modules (doom-emacs, logseq, logseq-cli) append their caches through
  # extra-substituters, so probe the union or their served outputs are
  # walked and misreported as local builds.
  mapfile -t substituters < <(nix_cmd eval --json \
    "${FLAKE_REF}#nixosConfigurations.${host}.config.nix.settings" \
    --accept-flake-config \
    --apply 's: (s.substituters or [ ]) ++ (s."extra-substituters" or [ ])' |
    jq -r '.[]')
  printf 'substituters (%s): %s\n' "${#substituters[@]}" "${substituters[*]}"

  # Probe bases: host substituters plus cache.nixos.org (dedup by base).
  declare -A base_seen=()
  probe_bases=()
  for sub in "https://cache.nixos.org" "${substituters[@]}"; do
    b="$(probe_base "${sub}")"
    [[ -z ${b} || -n ${base_seen[${b}]:-} ]] && continue
    base_seen["${b}"]=1
    probe_bases+=("${b}")
  done
  unset base_seen

  # Top-down walk. SEEN marks visited derivations; a derivation whose
  # output paths are all served (by any probe base) terminates its branch.
  declare -A SEEN=()
  SEEN["${toplevel_drv}"]=1
  frontier=("${toplevel_drv}")
  built_drvs=()
  substitutable_names=()
  : >"${tmp}/meta"

  host_system=""
  level=0
  while [[ ${#frontier[@]} -gt 0 ]]; do
    level=$((level + 1))
    printf 'cache-coverage: %s: walk level %s (%s derivations)\n' \
      "${host}" "${level}" "${#frontier[@]}" >&2
    : >"${tmp}/level.json.parts"
    for ((_i = 0; _i < ${#frontier[@]}; _i += DRV_SHOW_BATCH)); do
      nix_cmd derivation show "${frontier[@]:_i:DRV_SHOW_BATCH}" \
        >>"${tmp}/level.json.parts"
    done
    jq -s 'add' "${tmp}/level.json.parts" >"${tmp}/level.json"
    # drv, name, pname, version, fixed-output flag, system, space-joined
    # output paths, space-joined inputDrvs. Pipe-delimited: a tab in IFS is
    # IFS whitespace, so bash read would collapse empty fields; the store
    # name charset cannot contain a pipe.
    jq -r '
      to_entries[] | .key as $drv | .value as $d |
      [$drv,
       ($d.name // ""),
       ($d.env.pname // ""),
       ($d.env.version // ""),
       (if ($d.env.outputHash // "") != "" then "1" else "0" end),
       ($d.system // ""),
       ([$d.outputs[].path // empty] | join(" ")),
       (($d.inputDrvs // {}) | keys | join(" "))
      ] | join("|")' "${tmp}/level.json" >"${tmp}/level.tsv"

    while IFS='|' read -r _drv _name _pname _version _fod _system outpaths _inputs; do
      read -ra out_arr <<<"${outpaths}"
      for p in "${out_arr[@]}"; do
        h="${p##*/}"
        h="${h%%-*}"
        for b in "${probe_bases[@]}"; do
          printf '%s/%s.narinfo\n' "${b}" "${h}"
        done
      done
    done <"${tmp}/level.tsv" >"${tmp}/level.urls"
    probe_urls "${tmp}/level.urls"

    next_frontier=()
    while IFS='|' read -r drv name pname version fod sys outpaths inputs; do
      if [[ ${drv} == "${toplevel_drv}" ]]; then
        host_system="${sys}"
      fi
      served=1
      first_unserved=""
      if [[ -z ${outpaths} ]]; then
        served=0
      fi
      read -ra out_arr <<<"${outpaths}"
      for p in "${out_arr[@]}"; do
        h="${p##*/}"
        h="${h%%-*}"
        path_served=0
        for b in "${probe_bases[@]}"; do
          probe_key="${b}/${h}.narinfo"
          if [[ ${PROBE[${probe_key}]:-} == "200" ]]; then
            path_served=1
            break
          fi
        done
        if [[ ${path_served} -eq 0 ]]; then
          served=0
          [[ -z ${first_unserved} ]] && first_unserved="${p}"
        fi
      done
      if [[ ${served} -eq 1 ]]; then
        substitutable_names+=("${name}")
        continue
      fi
      built_drvs+=("${drv}")
      printf '%s|%s|%s|%s|%s|%s|%s\n' \
        "${drv}" "${name}" "${pname}" "${version}" "${fod}" "${sys}" \
        "${first_unserved}" >>"${tmp}/meta"
      read -ra input_arr <<<"${inputs}"
      for child in "${input_arr[@]}"; do
        [[ -n ${SEEN[${child}]:-} ]] && continue
        SEEN["${child}"]=1
        next_frontier+=("${child}")
      done
    done <"${tmp}/level.tsv"
    frontier=("${next_frontier[@]}")
  done
  unset SEEN

  printf 'substitutable: %s derivations\n' "${#substitutable_names[@]}"
  printf 'would build on a fresh machine: %s derivations\n' "${#built_drvs[@]}"

  if [[ ${#built_drvs[@]} -eq 0 ]]; then
    printf 'summary: %s OK (everything substitutable)\n' "${host}"
    continue
  fi

  # Candidate stock attribute names per derivation: pname, name minus the
  # trailing version, and pname plus version major (gtksourceview 4.8.4 is
  # attribute gtksourceview4). The local version comes from env.version,
  # else from the stripped name suffix; derivations without any version
  # (config texts, wrappers) never match a stock attribute.
  declare -A CAND1=() CAND2=() CAND3=() LOCAL_VER=()
  all_candidates=()
  while IFS='|' read -r drv name pname version _fod sys _outpath; do
    # Builds for a foreign system (the i686 support libraries pulled in by
    # nvidia and steam 32-bit userspace) can share a name with a host-system
    # attribute; the stock baseline is evaluated for the host system only,
    # so they never stock-match and stay in local-only.
    if [[ ${sys} != "${host_system}" ]]; then
      CAND1["${drv}"]=""
      CAND2["${drv}"]=""
      CAND3["${drv}"]=""
      LOCAL_VER["${drv}"]=""
      continue
    fi
    base="${name}"
    if [[ -n ${version} && ${name} == *"-${version}" ]]; then
      base="${name%-"${version}"}"
    else
      base="${name%%-[0-9]*}"
    fi
    local_ver="${version}"
    if [[ -z ${local_ver} && ${base} != "${name}" ]]; then
      local_ver="${name#"${base}"-}"
    fi
    major="${local_ver%%.*}"
    c1="${pname:-${base}}"
    c2=""
    c3=""
    [[ ${base} != "${c1}" ]] && c2="${base}"
    [[ -n ${major} && ${major} != "${local_ver}" ]] && c3="${c1}${major}"
    CAND1["${drv}"]="${c1}"
    CAND2["${drv}"]="${c2}"
    CAND3["${drv}"]="${c3}"
    LOCAL_VER["${drv}"]="${local_ver}"
    all_candidates+=("${c1}")
    [[ -n ${c2} ]] && all_candidates+=("${c2}")
    [[ -n ${c3} ]] && all_candidates+=("${c3}")
  done <"${tmp}/meta"

  # One batched evaluation of the raw nixpkgs input for every candidate.
  # Lix `nix eval` does not auto-call functions with --argstr, so the
  # values are spliced in. Every spliced value stays inside the nix store
  # name charset (no quotes, no dollar signs), so the quoting is safe.
  names_nix="$(printf '%s\n' "${all_candidates[@]}" | sort -u | jq -R -r '@json' | paste -sd' ' -)"
  # shellcheck disable=SC2016 # ${n} is nix antiquotation, not shell
  nix_cmd eval --json --expr '
    let
      np = builtins.fetchTree {
        type = "github";
        owner = "'"${NIXPKGS_OWNER}"'";
        repo = "'"${NIXPKGS_REPO}"'";
        rev = "'"${NIXPKGS_REV}"'";
        narHash = "'"${NIXPKGS_NARHASH}"'";
      };
      lp = import np {
        system = "'"${host_system}"'";
        config = { allowUnfree = true; };
        overlays = [ ];
      };
      # tryEval per field, forcing to a string inside the tryEval: a
      # tryEval around the attrset only reaches weak head normal form, so
      # throws from insecure/broken packages would escape at printing time.
      probe = n:
        if !(lp ? ${n}) then
          null
        else
          let
            pR = builtins.tryEval (
              let q = lp.${n}.outPath or null;
              in if builtins.isString q then q else null
            );
            vR = builtins.tryEval (
              let w = lp.${n}.version or "";
              in if builtins.isString w then w else ""
            );
            mR = builtins.tryEval (
              let d = lp.${n}.name or "";
              in if builtins.isString d then d else ""
            );
          in
          {
            p = if pR.success then pR.value else null;
            v = if vR.success then vR.value else "";
            m = if mR.success then mR.value else "";
          };
    in
    builtins.listToAttrs (map (n: { name = n; value = probe n; })
      [ '"${names_nix}"' ])
  ' >"${tmp}/stock.json"

  # Preloaded maps: one jq pass instead of three jq processes per row.
  declare -A STOCKP=() STOCKV=() STOCKN=()
  while IFS='|' read -r a p v m; do
    [[ -z ${a} ]] && continue
    STOCKP["${a}"]="${p}"
    STOCKV["${a}"]="${v}"
    STOCKN["${a}"]="${m}"
  done < <(jq -r '
    to_entries[] |
    [.key, (.value.p // ""), (.value.v // ""), (.value.m // "")] |
    join("|")' "${tmp}/stock.json")

  # Pick the candidate whose stock version equals the local version, or
  # whose stock derivation name equals the local one (wrappers without a
  # version attribute, overlays that keep the name). No looser fallback:
  # name prefixes of unrelated packages (a config dir named dbus-1 vs the
  # dbus package) must not count as divergence. No pipe on this loop: it
  # fills the STOCK_* maps in the current shell.
  declare -A STOCK_ATTR=() STOCK_PATH=()
  : >"${tmp}/stock.urls"
  while IFS='|' read -r drv name _pname version _fod _sys _outpath; do
    chosen_attr=""
    chosen_path=""
    local_ver="${LOCAL_VER[${drv}]}"
    for cand in "${CAND1[${drv}]}" "${CAND2[${drv}]}" "${CAND3[${drv}]}"; do
      [[ -z ${cand} ]] && continue
      p="${STOCKP[${cand}]:-}"
      [[ -z ${p} ]] && continue
      sv="${STOCKV[${cand}]:-}"
      sn="${STOCKN[${cand}]:-}"
      if { [[ -n ${local_ver} && ${sv} == "${local_ver}" ]]; } ||
        [[ -n ${sn} && ${sn} == "${name}" ]]; then
        chosen_attr="${cand}"
        chosen_path="${p}"
        break
      fi
    done
    STOCK_ATTR["${drv}"]="${chosen_attr}"
    STOCK_PATH["${drv}"]="${chosen_path}"
    if [[ -n ${chosen_path} ]]; then
      h="${chosen_path##*/}"
      printf 'https://cache.nixos.org/%s.narinfo\n' "${h%%-*}" \
        >>"${tmp}/stock.urls"
    fi
  done <"${tmp}/meta"
  probe_urls "${tmp}/stock.urls"

  unexpected=()
  allowlisted_entries=()
  diverged_uncached=()
  uncached_stock=()
  fetch_drvs=()
  local_only=()
  host_unexpected_size=0

  while IFS='|' read -r drv name pname _version fod _sys outpath; do
    attr="${STOCK_ATTR[${drv}]}"
    spath="${STOCK_PATH[${drv}]}"

    if [[ ${fod} == "1" ]]; then
      fetch_drvs+=("${name}")
      continue
    fi
    if [[ -z ${spath} ]]; then
      local_only+=("${name}")
      continue
    fi
    if [[ ${spath} == "${outpath}" ]]; then
      uncached_stock+=("${name}")
      continue
    fi
    stock_url="https://cache.nixos.org/$(hash_part "${spath}").narinfo"
    stock_code="${PROBE[${stock_url}]:-000}"
    if [[ ${stock_code} != "200" ]]; then
      diverged_uncached+=("${name} (stock ${attr} not served, http ${stock_code})")
      continue
    fi
    narsize="$(fetch_narsize "${stock_url}")"
    hint="$(git -C "${FLAKE_DIR}" grep -l --fixed-strings -- "${pname:-${attr}}" \
      -- 'modules/*.nix' 2>/dev/null | head -n 3 | paste -sd, - || true)"
    entry="${name}"
    entry+=$'\n'"      actual: ${outpath:-?} (no configured substituter serves it)"
    entry+=$'\n'"      stock:  ${spath}"
    entry+=$'\n'"              attr ${attr}, nar $(human "${narsize}"), cache.nixos.org 200"
    if [[ -n ${hint} ]]; then
      entry+=$'\n'"      hint: ${hint}"
    fi
    if allowlisted "${name}" || { [[ -n ${pname} ]] && allowlisted "${pname}"; }; then
      allowlisted_entries+=("${entry}")
    else
      unexpected+=("${entry}")
      [[ -n ${narsize} ]] && host_unexpected_size=$((host_unexpected_size + narsize))
    fi
  done <"${tmp}/meta"

  print_group "unexpected-local" "overlay/override diverged from a served stock path" \
    "${#unexpected[@]}" "${unexpected[@]}"
  print_group "allowlisted" "accepted divergence" \
    "${#allowlisted_entries[@]}" "${allowlisted_entries[@]}"
  print_group "diverged-uncached" "diverged, stock unserved too" \
    "${#diverged_uncached[@]}" "${diverged_uncached[@]}"
  print_group "uncached-stock" "same path as stock, not yet published" \
    "${#uncached_stock[@]}" "${uncached_stock[@]}"
  print_group "fetch" "fixed-output source downloads" \
    "${#fetch_drvs[@]}" "${fetch_drvs[@]}"
  local_only_sorted=()
  if [[ ${#local_only[@]} -gt 0 ]]; then
    mapfile -t local_only_sorted < <(printf '%s\n' "${local_only[@]}" | sort)
  fi
  print_group "local-only" "no stock counterpart: config texts, units, wrappers, custom packages, foreign-system builds" \
    "${#local_only_sorted[@]}" "${local_only_sorted[@]}"
  if [[ ${VERBOSE} == "true" ]]; then
    substitutable_sorted=()
    if [[ ${#substitutable_names[@]} -gt 0 ]]; then
      mapfile -t substitutable_sorted < <(printf '%s\n' "${substitutable_names[@]}" | sort)
    fi
    print_group "substitutable" "served by a probe base; walk stops here" \
      "${#substitutable_sorted[@]}" "${substitutable_sorted[@]}"
  fi

  host_unexpected=${#unexpected[@]}
  TOTAL_UNEXPECTED=$((TOTAL_UNEXPECTED + host_unexpected))
  TOTAL_UNEXPECTED_SIZE=$((TOTAL_UNEXPECTED_SIZE + host_unexpected_size))
  if [[ ${host_unexpected} -gt 0 ]]; then
    printf 'summary: %s FAIL (%s unexpected, stock nar %s)\n' \
      "${host}" "${host_unexpected}" "$(human "${host_unexpected_size}")"
  else
    printf 'summary: %s OK\n' "${host}"
  fi
done

printf '\n'
if [[ ${PROBE_ERRORS} -gt 0 ]]; then
  printf 'warning: %s narinfo probes failed with network errors; unserved classifications may be wrong\n' \
    "${PROBE_ERRORS}"
fi
if [[ ${TOTAL_UNEXPECTED} -gt ${MAX_COUNT} || ${TOTAL_UNEXPECTED_SIZE} -gt ${MAX_SIZE} ]]; then
  printf 'result: FAIL (%s unexpected-local, stock nar %s; thresholds: count %s, size %s)\n' \
    "${TOTAL_UNEXPECTED}" "$(human "${TOTAL_UNEXPECTED_SIZE}")" \
    "${MAX_COUNT}" "$(human "${MAX_SIZE}")"
  exit 1
fi
printf 'result: OK (%s unexpected-local)\n' "${TOTAL_UNEXPECTED}"
