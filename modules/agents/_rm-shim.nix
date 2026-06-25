# Shared rm -> rip shim for terminal coding agents.
#
# Both the codex and claude-code shell wrappers rewrite bare `rm` to a
# recoverable, rip-backed deletion. Keeping the shim here is the single source
# of truth so the two agents cannot drift on deletion semantics.
{ lib, pkgs }:
# Translate common rm flags into rip so agents default to recoverable deletions.
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
