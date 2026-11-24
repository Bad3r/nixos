# Controlled bash wrapper and rm -> trash shim for Antigravity CLI and Hub.
# Antigravity runs `run_command` via `bash` from PATH, so prepending this dir
# intercepts tool shells while stripping itself before eval avoids recursion.
{
  lib,
  pkgs,
  scratchDir,
}:
let
  rmShim = import ../_rm-shim.nix { inherit lib pkgs; };
  sessionTmpdir = import ../_session-tmpdir.nix { inherit lib scratchDir; };

  antigravityBashWrapper = pkgs.writeShellScriptBin "bash" ''
    set -euo pipefail

    direnvBin=${lib.getExe pkgs.direnv}
    realBash=${lib.getExe pkgs.bashInteractive}
    rmShimPath=${rmShim}/bin/rm
    selfPath="''${BASH_SOURCE[0]}"
    case "$selfPath" in
      */*)
        selfDir="''${selfPath%/*}"
        selfDir="''${selfDir:-/}"
        ;;
      *) selfDir="." ;;
    esac
    selfBin="$(cd -- "$selfDir" && pwd -P)"
    unset selfPath selfDir

    newPath=""
    if [ -n "''${PATH:-}" ]; then
      IFS=: read -ra pathParts <<<"$PATH"
      for dir in "''${pathParts[@]}"; do
        [ -n "$dir" ] || continue
        [ "''${dir%/}" = "$selfBin" ] && continue
        newPath="''${newPath:+$newPath:}$dir"
      done
    fi
    export PATH=${rmShim}/bin''${newPath:+:$newPath}

    ${sessionTmpdir "ANTIGRAVITY_CONVERSATION_ID"}
    # Restricted terminal sandboxes may not mount scratchDir writable; fall back to /tmp.
    if [ -z "''${TMPDIR:-}" ] || [ ! -d "$TMPDIR" ] || [ ! -w "$TMPDIR" ]; then
      export TMPDIR=/tmp
    fi

    originalArgs=("$@")
    options=()
    haveCommand=0
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -- | -)
          options+=("$1")
          shift
          break
          ;;
        -rcfile | --rcfile | -init-file | --init-file | -o | +o | -O | +O)
          options+=("$1")
          shift
          if [ "$#" -gt 0 ]; then
            options+=("$1")
            shift
          fi
          ;;
        --*)
          options+=("$1")
          shift
          ;;
        -norc | -noprofile | -posix | -restricted | -verbose | -login | -noediting | -nobraceexpansion | -nolineediting | -dump-strings | -dump-po-strings | -wordexp | -debugger | -help | -version | -rpm-requires)
          options+=("$1")
          shift
          ;;
        -*)
          case "$1" in
            *c*) haveCommand=1 ;;
          esac
          options+=("$1")
          shift
          ;;
        +*)
          options+=("$1")
          shift
          ;;
        *)
          break
          ;;
      esac
    done

    if [ "$haveCommand" -eq 1 ] && [ "$#" -ge 1 ]; then
      export ANTIGRAVITY_WRAPPED_COMMAND="$1"
      shift

      exec "$realBash" "''${options[@]}" '
        _agyCmd="''${ANTIGRAVITY_WRAPPED_COMMAND:-}"
        unset ANTIGRAVITY_WRAPPED_COMMAND
        if direnvExports="$("'"$direnvBin"'" export bash 2>/dev/null || true)"; then
          eval "$direnvExports"
        fi
        export PATH=${rmShim}/bin''${PATH:+:$PATH}
        rm() {
          "'"$rmShimPath"'" "$@"
        }
        eval -- "$_agyCmd"
      ' "$@"
    fi

    exec "$realBash" "''${originalArgs[@]}"
  '';
in
{
  inherit
    antigravityBashWrapper
    rmShim
    ;
}
