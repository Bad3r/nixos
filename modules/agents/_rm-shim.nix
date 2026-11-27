# Shared rm shim: the codex, claude-code, and antigravity-cli wrappers route bare
# `rm` through rip so deletions stay recoverable. Only rm's own flags pass;
# rip's other modes (--empty-trash, --unbury, --graveyard, ...) stay out of reach.
{ lib, pkgs }:
let
  rip = pkgs.callPackage ../../packages/rip { };
in
pkgs.writeShellScriptBin "rm" ''
  set -euo pipefail

  force=0
  verbose=0
  one_file_system=0
  operands=()

  unsupported() {
    echo "rm shim: unsupported rm option '$1'; supported: -f, -r, -R, -d, -v, --force, --recursive, --dir, --verbose, --one-file-system" >&2
    exit 2
  }

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --)
        shift
        operands+=("$@")
        break
        ;;
      -f | --force) force=1 ;;
      -r | -R | --recursive | -d | --dir) ;;
      -v | --verbose) verbose=1 ;;
      --one-file-system) one_file_system=1 ;;
      --*) unsupported "$1" ;;
      -?*)
        bundle="''${1#-}"
        if [ -n "''${bundle//[dfRrv]/}" ]; then
          unsupported "$1"
        fi
        case "$bundle" in
          *f*) force=1 ;;
        esac
        case "$bundle" in
          *v*) verbose=1 ;;
        esac
        ;;
      *) operands+=("$1") ;;
    esac
    shift
  done

  if [ "''${#operands[@]}" -eq 0 ]; then
    if [ "$force" -eq 1 ]; then
      exit 0
    fi
    echo "rm: missing operand" >&2
    exit 1
  fi

  flags=()
  if [ "$force" -eq 1 ]; then
    flags+=(-f)
  fi
  if [ "$verbose" -eq 1 ]; then
    flags+=(-v)
  fi
  if [ "$one_file_system" -eq 1 ]; then
    flags+=(--one-file-system)
  fi
  exec ${lib.getExe' rip "rip"} "''${flags[@]}" -- "''${operands[@]}"
''
