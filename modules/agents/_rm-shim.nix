# Shared rm shim: the codex, claude-code, and antigravity-cli wrappers route bare
# `rm` through it to trash-cli's trash-put so deletions stay recoverable.
{ lib, pkgs }:
pkgs.writeShellScriptBin "rm" ''
  set -euo pipefail

  force=0
  verbose=0
  one_file_system=0
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
      -r|-R|--recursive|-d|--dir)
        shift
        ;;
      -v|--verbose)
        verbose=1
        shift
        ;;
      --one-file-system)
        one_file_system=1
        shift
        ;;
      -[!-]*)
        bundle="''${1#-}"
        unsupported="''${bundle//[dfRrv]/}"
        if [ -n "$unsupported" ]; then
          echo "rm shim: unsupported rm option '$1'; supported: -f, -r, -R, -d, -v, --one-file-system" >&2
          exit 2
        fi
        case "$bundle" in
          *f*)
            force=1
            ;;
        esac
        case "$bundle" in
          *v*)
            verbose=1
            ;;
        esac
        shift
        ;;
      --*)
        echo "rm shim: unsupported rm option '$1'; supported: -f, -r, -R, -d, -v, --one-file-system" >&2
        exit 2
        ;;
      *)
        operands+=("$1")
        shift
        ;;
    esac
  done

  # trash-put cannot rename a mount point; shutil.move then falls back to
  # copy-and-delete, which empties the mount and discards the copy. trash-put
  # also
  # moves a directory together with any mount inside it, and a later
  # trash-empty deletes through that mount. Trashing cannot skip a subtree the
  # way GNU rm --one-file-system does, so an operand holding a mount stays.
  status=0
  kept=()
  if [ "''${#operands[@]}" -gt 0 ]; then
    if ! mountinfo="$(< /proc/self/mountinfo)"; then
      echo "rm shim: cannot read /proc/self/mountinfo to protect mount points" >&2
      exit 1
    fi
  fi
  for op in "''${operands[@]}"; do
    # os.path.normpath, as trash-put applies before it moves the path.
    abs=0
    case "$op" in
      /*) abs=1 ;;
    esac
    parts=()
    rest="$op"
    while [ -n "$rest" ]; do
      comp="''${rest%%/*}"
      case "$rest" in
        */*) rest="''${rest#*/}" ;;
        *) rest="" ;;
      esac
      case "$comp" in
        "" | .) ;;
        ..)
          if [ "''${#parts[@]}" -gt 0 ] && [ "''${parts[-1]}" != .. ]; then
            unset 'parts[-1]'
          elif [ "$abs" -eq 0 ]; then
            parts+=(..)
          fi
          ;;
        *) parts+=("$comp") ;;
      esac
    done
    norm=""
    for comp in "''${parts[@]}"; do
      norm="''${norm:+$norm/}$comp"
    done
    if [ "$abs" -eq 1 ]; then
      norm="/$norm"
    elif [ -z "$norm" ]; then
      norm=.
    fi

    if [ -L "$norm" ] || [ ! -e "$norm" ]; then
      kept+=("$op")
      continue
    fi
    case "$norm" in
      */*)
        parent="''${norm%/*}"
        base="''${norm##*/}"
        ;;
      *)
        parent=.
        base="$norm"
        ;;
    esac
    case "$base" in
      . | ..)
        parent="$norm"
        base=""
        ;;
    esac
    case "$parent" in
      "") parent=/ ;;
      /*) ;;
      *) parent="./$parent" ;;
    esac
    # The trailing dot keeps newlines at the end of the path.
    if ! canon="$(cd -P -- "$parent" && pwd -P && echo .)"; then
      echo "rm shim: cannot resolve '$op' to check for mount points" >&2
      status=1
      continue
    fi
    canon="''${canon%$'\n.'}"
    if [ -n "$base" ]; then
      canon="''${canon%/}/$base"
    fi

    # mountinfo octal-escapes backslash, space, tab, and newline.
    enc="''${canon//\\/\\134}"
    enc="''${enc// /\\040}"
    enc="''${enc//$'\t'/\\011}"
    enc="''${enc//$'\n'/\\012}"
    prefix="''${enc%/}/"
    refusal=""
    while read -r _ _ _ _ mount_point _; do
      if [ "$mount_point" = "$enc" ]; then
        refusal="'$op' is a mount point, which trash-put cannot move intact"
        break
      fi
      if [ "$one_file_system" -eq 1 ]; then
        case "$mount_point" in
          "$prefix"?*)
            refusal="mount point '$mount_point' lies inside '$op' (--one-file-system)"
            break
            ;;
        esac
      fi
    done <<< "$mountinfo"
    if [ -n "$refusal" ]; then
      echo "rm shim: skipping '$op': $refusal" >&2
      status=1
      continue
    fi
    kept+=("$op")
  done
  if [ "''${#kept[@]}" -eq 0 ] && [ "$status" -ne 0 ]; then
    exit "$status"
  fi
  operands=("''${kept[@]}")

  cmd=(${lib.getExe' pkgs.trash-cli "trash-put"})
  if [ "$force" -eq 1 ]; then
    cmd+=(-f)
  fi
  if [ "$verbose" -eq 1 ]; then
    cmd+=(-v)
  fi

  if [ "''${#operands[@]}" -eq 0 ]; then
    exec "''${cmd[@]}"
  fi

  if [ "$status" -eq 0 ]; then
    exec "''${cmd[@]}" -- "''${operands[@]}"
  fi
  "''${cmd[@]}" -- "''${operands[@]}" || true
  exit "$status"
''
