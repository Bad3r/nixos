#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

prog_name="${0##*/}"

usage() {
  cat <<EOF
Usage: ${prog_name}

Report the running, activated, and booted NixOS kernels. The activated and
booted kernel images and module trees are compared to detect a pending kernel
reboot.

Exit status:
  0  no kernel change is pending
  1  the activated kernel differs from the booted kernel
  2  invalid arguments or missing NixOS runtime state
EOF
}

error_msg() {
  printf '%s: %s\n' "${prog_name}" "$1" >&2
}

die() {
  error_msg "$1"
  exit 2
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    die "required command not found: $1"
  fi
}

resolve_runtime_path() {
  local label="$1"
  local path="$2"
  local resolved

  if [[ ! -e ${path} && ! -L ${path} ]]; then
    die "${label} path does not exist: ${path}"
  fi

  if ! resolved="$(readlink -f -- "${path}")" || [[ -z ${resolved} ]]; then
    die "cannot resolve ${label} path: ${path}"
  fi

  printf '%s' "${resolved}"
}

kernel_releases() {
  local label="$1"
  local modules_dir="/run/${label}-system/kernel-modules/lib/modules"
  local releases

  if [[ ! -d ${modules_dir} ]]; then
    die "${label} kernel modules directory does not exist: ${modules_dir}"
  fi

  if ! releases="$(find "${modules_dir}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n')"; then
    die "cannot inspect ${label} kernel modules directory: ${modules_dir}"
  fi
  if [[ -z ${releases} ]]; then
    die "no ${label} kernel module release found in: ${modules_dir}"
  fi

  printf '%s' "${releases}"
}

case "$#" in
0)
  ;;
1)
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
  esac
  ;;
*)
  usage >&2
  exit 2
  ;;
esac

require_cmd find
require_cmd readlink
require_cmd uname

if ! running_kernel="$(uname -r)" || [[ -z ${running_kernel} ]]; then
  die "cannot determine the running kernel"
fi

activated_kernel_image="$(resolve_runtime_path \
  'activated kernel' /run/current-system/kernel)"
booted_kernel_image="$(resolve_runtime_path \
  'booted kernel' /run/booted-system/kernel)"
activated_kernel_modules="$(resolve_runtime_path \
  'activated kernel modules' /run/current-system/kernel-modules)"
booted_kernel_modules="$(resolve_runtime_path \
  'booted kernel modules' /run/booted-system/kernel-modules)"
activated_releases="$(kernel_releases current)"
booted_releases="$(kernel_releases booted)"

printf 'Running kernel: %s\n' "${running_kernel}"
printf 'Activated kernel release(s): %s\n' "${activated_releases//$'\n'/, }"
printf 'Booted kernel release(s): %s\n' "${booted_releases//$'\n'/, }"
printf 'Activated kernel image: %s\n' "${activated_kernel_image}"
printf 'Booted kernel image: %s\n' "${booted_kernel_image}"
printf 'Activated kernel modules: %s\n' "${activated_kernel_modules}"
printf 'Booted kernel modules: %s\n' "${booted_kernel_modules}"

if [[ ${activated_kernel_image} == "${booted_kernel_image}" &&
  ${activated_kernel_modules} == "${booted_kernel_modules}" ]]; then
  printf 'Result: no kernel change is pending; a kernel reboot is not required.\n'
  exit 0
fi

printf 'Result: the activated kernel differs from the booted kernel; reboot is required.\n'
exit 1
