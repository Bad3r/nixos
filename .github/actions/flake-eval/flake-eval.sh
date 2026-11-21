#!/usr/bin/env bash
# flake-eval - pure evaluation of one attribute of a flake, for the review
# agents that action.yml in this directory installs it for.
#
# Usage:
#   flake-eval.sh <flake-directory> [--json | --raw] <attribute> [<apply-expression>]
#
# The installed flake-eval launcher fixes the directory and the agent passes the
# rest. The agent reads text that anyone can post on a pull request, so this is
# its only route to Nix. The fixed argument shape leaves no way to pass
# --impure, --expr or --option, flake.nix#nixConfig stays unapplied because it
# can load plugins and enable builtins.exec, and the emptied environment keeps
# the job's tokens out of the evaluator.

set -euo pipefail

usage() {
	echo "usage: flake-eval [--json | --raw] <attribute> [<apply-expression>]" >&2
	exit 2
}

if [ "$#" -lt 1 ]; then
	usage
fi
flake=$1
shift

format=()
case "${1:-}" in
--json | --raw)
	format=("$1")
	shift
	;;
esac

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || [ -z "$1" ]; then
	usage
fi

args=("${format[@]}" "path:$flake#$1")
if [ "$#" -eq 2 ]; then
	args+=(--apply "$2")
fi

exec env -i HOME="$HOME" PATH="$PATH" \
	nix eval --no-accept-flake-config "${args[@]}"
