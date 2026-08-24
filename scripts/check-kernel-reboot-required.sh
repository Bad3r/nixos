#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

prog_name="${0##*/}"
output_format="json"

usage() {
  cat <<EOF
Usage: ${prog_name} [--json | --text]

Report the running, activated, and booted NixOS kernels. The activated and
booted kernel images and module trees are compared to detect a pending kernel
reboot.

Options:
  --json      Emit a machine-readable report on stdout (default).
  --text      Emit a human-readable report on stdout.
  -h, --help  Show this help message.

JSON keys:
  reboot_required  true, false, or null when the report could not be produced
  reason           one sentence describing the verdict
  changed          subset of ["kernel", "kernel_modules"] that differs
  running_kernel   'uname -r' of the currently running kernel
  activated        object with system, kernel, kernel_modules, kernel_releases
  booted           object with the same keys for the booted generation
  error            present only when reboot_required is null

Exit status:
  0  no kernel change is pending
  1  the activated kernel differs from the booted kernel
  2  invalid arguments or missing NixOS runtime state
EOF
}

error_msg() {
  printf '%s: %s\n' "${prog_name}" "$1" >&2
}

json_string() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '"%s"' "${value}"
}

json_string_array() {
  local out="["
  local first=1
  local item
  for item in "$@"; do
    if [[ ${first} -eq 0 ]]; then
      out+=","
    fi
    first=0
    out+="$(json_string "${item}")"
  done
  printf '%s]' "${out}"
}

join_comma() {
  local out=""
  local item
  for item in "$@"; do
    if [[ -n ${out} ]]; then
      out+=", "
    fi
    out+="${item}"
  done
  printf '%s' "${out}"
}

# Keeps stdout parseable for the failure paths a caller has to distinguish from
# "no reboot pending": every one of them exits 2, which is otherwise reported
# on stderr alone.
die() {
  error_msg "$1"
  if [[ ${output_format} == "json" ]]; then
    printf '{\n  "reboot_required": null,\n  "error": %s\n}\n' "$(json_string "$1")"
  fi
  exit 2
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    die "required command not found: $1"
  fi
}

# Assigns through a caller-named variable rather than stdout so `die` runs in
# the main shell: from a command substitution it would exit only the subshell,
# and its JSON body would land in the variable being assigned.
resolve_runtime_path() {
  local label="$1"
  local path="$2"
  local out_var="$3"
  local resolved

  if [[ ! -e ${path} && ! -L ${path} ]]; then
    die "${label} path does not exist: ${path}"
  fi

  if ! resolved="$(readlink -f -- "${path}")" || [[ -z ${resolved} ]]; then
    die "cannot resolve ${label} path: ${path}"
  fi

  printf -v "${out_var}" '%s' "${resolved}"
}

kernel_releases() {
  local label="$1"
  local out_var="$2"
  local modules_dir="/run/${label}-system/kernel-modules/lib/modules"
  local releases

  if [[ ! -d ${modules_dir} ]]; then
    die "${label} kernel modules directory does not exist: ${modules_dir}"
  fi

  # Sorted so the JSON report is byte-stable across runs; find walks the
  # directory in whatever order the filesystem returns.
  if ! releases="$(find "${modules_dir}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)"; then
    die "cannot inspect ${label} kernel modules directory: ${modules_dir}"
  fi
  if [[ -z ${releases} ]]; then
    die "no ${label} kernel module release found in: ${modules_dir}"
  fi

  mapfile -t "${out_var}" <<<"${releases}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --json)
    output_format="json"
    shift
    ;;
  --text)
    output_format="text"
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    error_msg "unknown argument: $1"
    usage >&2
    exit 2
    ;;
  esac
done

require_cmd find
require_cmd readlink
require_cmd sort
require_cmd uname

if ! running_kernel="$(uname -r)" || [[ -z ${running_kernel} ]]; then
  die "cannot determine the running kernel"
fi

# Declared ahead of the calls that fill them: shellcheck cannot follow a
# `printf -v`/`mapfile` target through a variable holding the name (SC2154).
activated_system=""
booted_system=""
activated_kernel_image=""
booted_kernel_image=""
activated_kernel_modules=""
booted_kernel_modules=""
activated_releases=()
booted_releases=()

resolve_runtime_path 'activated system' /run/current-system activated_system
resolve_runtime_path 'booted system' /run/booted-system booted_system
resolve_runtime_path 'activated kernel' /run/current-system/kernel activated_kernel_image
resolve_runtime_path 'booted kernel' /run/booted-system/kernel booted_kernel_image
resolve_runtime_path 'activated kernel modules' /run/current-system/kernel-modules activated_kernel_modules
resolve_runtime_path 'booted kernel modules' /run/booted-system/kernel-modules booted_kernel_modules
kernel_releases current activated_releases
kernel_releases booted booted_releases

changed=()
if [[ ${activated_kernel_image} != "${booted_kernel_image}" ]]; then
  changed+=("kernel")
fi
if [[ ${activated_kernel_modules} != "${booted_kernel_modules}" ]]; then
  changed+=("kernel_modules")
fi

if [[ ${#changed[@]} -eq 0 ]]; then
  reboot_required="false"
  reason="no kernel change is pending; a kernel reboot is not required"
  exit_code=0
else
  reboot_required="true"
  reason="the activated kernel differs from the booted kernel; reboot is required"
  exit_code=1
fi

if [[ ${output_format} == "text" ]]; then
  printf 'Running kernel: %s\n' "${running_kernel}"
  printf 'Activated kernel release(s): %s\n' "$(join_comma "${activated_releases[@]}")"
  printf 'Booted kernel release(s): %s\n' "$(join_comma "${booted_releases[@]}")"
  printf 'Activated kernel image: %s\n' "${activated_kernel_image}"
  printf 'Booted kernel image: %s\n' "${booted_kernel_image}"
  printf 'Activated kernel modules: %s\n' "${activated_kernel_modules}"
  printf 'Booted kernel modules: %s\n' "${booted_kernel_modules}"
  printf 'Result: %s.\n' "${reason}"
  exit "${exit_code}"
fi

printf '{\n'
printf '  "reboot_required": %s,\n' "${reboot_required}"
printf '  "reason": %s,\n' "$(json_string "${reason}")"
printf '  "changed": %s,\n' "$(json_string_array "${changed[@]}")"
printf '  "running_kernel": %s,\n' "$(json_string "${running_kernel}")"
printf '  "activated": {\n'
printf '    "system": %s,\n' "$(json_string "${activated_system}")"
printf '    "kernel": %s,\n' "$(json_string "${activated_kernel_image}")"
printf '    "kernel_modules": %s,\n' "$(json_string "${activated_kernel_modules}")"
printf '    "kernel_releases": %s\n' "$(json_string_array "${activated_releases[@]}")"
printf '  },\n'
printf '  "booted": {\n'
printf '    "system": %s,\n' "$(json_string "${booted_system}")"
printf '    "kernel": %s,\n' "$(json_string "${booted_kernel_image}")"
printf '    "kernel_modules": %s,\n' "$(json_string "${booted_kernel_modules}")"
printf '    "kernel_releases": %s\n' "$(json_string_array "${booted_releases[@]}")"
printf '  }\n'
printf '}\n'
exit "${exit_code}"
