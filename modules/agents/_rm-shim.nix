# Shared rm -> rip shim: the codex and claude-code wrappers both route bare `rm`
# through it so deletions stay recoverable.
{ lib, pkgs }:
pkgs.writeShellScriptBin "rm" ''
  set -euo pipefail

  force=0
  operands=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --)
        shift
        while [ "$#" -gt 0 ]; do
          operands+=("$1")
          shift
        done
        break
        ;;
      -f|--force)
        force=1
        shift
        ;;
      -r|-R|--recursive)
        shift
        ;;
      -[!-]*)
        bundle="''${1#-}"
        unsupported="''${bundle//[fRr]/}"
        if [ -n "$unsupported" ]; then
          echo "rm shim: unsupported rm option '$1'; use rip directly for nonstandard flags" >&2
          exit 2
        fi
        case "$bundle" in
          *f*)
            force=1
            ;;
        esac
        shift
        ;;
      --*)
        echo "rm shim: unsupported rm option '$1'; use rip directly for nonstandard flags" >&2
        exit 2
        ;;
      *)
        operands+=("$1")
        shift
        ;;
    esac
  done

  cmd=(${lib.getExe' pkgs.trash-cli "trash-put"})
  if [ "$force" -eq 1 ]; then
    cmd+=(-f)
  fi

  if [ "''${#operands[@]}" -eq 0 ]; then
    exec "''${cmd[@]}"
  fi

  exec "''${cmd[@]}" -- "''${operands[@]}"
''
