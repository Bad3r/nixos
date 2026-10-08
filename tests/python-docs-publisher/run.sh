#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

if ! publisher="$(command -v git-mirror-publish-python-docs)"; then
  printf '%s\n' 'run.sh: git-mirror-publish-python-docs is not on PATH' >&2
  exit 2
fi

tmpdir="$(mktemp -d)"
cleanup() {
  if [[ -d ${tmpdir} ]]; then
    rm -r "${tmpdir}"
  fi
}
trap cleanup EXIT

repo="${tmpdir}/repo"
mkdir -p "${repo}/Doc/library"
git -C "${repo}" init -q -b main
git -C "${repo}" config user.email publisher-test@example.invalid
git -C "${repo}" config user.name "Python docs publisher test"
: >"${repo}/Doc/conf.py"
: >"${repo}/Doc/contents.rst"
: >"${repo}/Doc/library/index.rst"
git -C "${repo}" add Doc
git -C "${repo}" commit -q -m 'add Python docs fixture'
git -C "${repo}" update-ref refs/remotes/origin/3.14 HEAD

cd "${tmpdir}"
if "${publisher}" >stdout.log 2>stderr.log; then
  printf '%s\n' 'publisher accepted a truncated versions page' >&2
  exit 1
else
  publisher_status=$?
fi
if [[ ${publisher_status} -ne 18 ]]; then
  printf 'publisher returned %s after curl exited 18\n' "${publisher_status}" >&2
  cat stderr.log >&2
  exit 1
fi
if ! grep -Fq 'curl: (18) transfer closed with 4 bytes remaining' stderr.log; then
  printf '%s\n' 'curl failure was not reported' >&2
  cat stderr.log >&2
  exit 1
fi
if [[ -e output/current || -e output/current-branch || -d output/revisions ]]; then
  printf '%s\n' 'publisher created output from the partial versions page' >&2
  exit 1
fi

printf '%s\n' 'ok: curl failure prevents publishing from a partial versions page'
