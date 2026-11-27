{
  coreutils,
  gnugrep,
  trash-cli,
  writeShellApplication,
}:

writeShellApplication {
  name = "rip";
  runtimeInputs = [
    coreutils
    gnugrep
    trash-cli
  ];
  text = ''
    TRASH_DIR_ARGS=()
    FORCE=false
    VERBOSE=false
    UNBURY=false
    EMPTY_TRASH=false
    SEANCE=false
    INSPECT=false
    ONE_FILE_SYSTEM=false
    UNBURY_FILES=()
    FILES=()

    usage() {
      cat >&2 <<'EOF'
    rip - safe rm alternative backed by trash-cli

    Moves files and directories to the trash instead of deleting them
    permanently. Cross-device moves (e.g. USB drives) are handled correctly
    via per-device .Trash-<uid>/ directories following the FreeDesktop Trash
    specification; the home-partition trash lives at ~/.local/share/Trash.

    An operand that is itself a mount point is skipped with exit status 1:
    trash-put cannot move it intact.

    Usage: rip [OPTIONS] [FILES]...

    Arguments:
      [FILES]...              Files or directories to move to trash.

    Options:
      -u, --unbury [<PATH>...]
            Restore trashed files via trash-restore. Without arguments,
            opens the global interactive picker. With one or more PATHs,
            restores each file by exact original location (relative paths
            resolve against the current directory; symlinks in parent
            components are not followed, mirroring trash-cli's recorded
            path). Multi-arg invocations are best-effort: the exit code
            is the first non-zero rc seen, and remaining files are still
            attempted.

      -s, --seance
            List files deleted from the current working directory, sourced
            from trash-list filtered by the current path prefix.

      --empty-trash
            Permanently delete all files in the trash (trash-empty).
            Prompts for confirmation unless --force is given. Requires a
            TTY when prompting; non-interactive callers must pass --force.

      -i, --inspect
            Print file info (ls -la) before trashing and prompt for
            confirmation. Requires a TTY unless --force is given.

      --graveyard <PATH>
            Override the trash directory for this invocation. Passed as
            --trash-dir to trash-put, trash-list, trash-empty, and
            trash-restore. The --unbury PATH argument independently
            selects which entry to restore.

      -f, --force
            Skip all confirmation prompts. Also silences nonexistent-file
            errors from trash-put (equivalent to rm -f).

      -r, -R, -d, --recursive, --dir
            Accepted and ignored for rm compatibility. trash-put handles
            directories natively so recursive and empty-dir flags are
            redundant. Enables muscle-memory usage like: rip -rfd path/

      --one-file-system
            Skip, with exit status 1, any operand that holds a mount point.
            Trashing moves a directory whole, mounts included, so the
            operand is kept instead of skipping only the mounted subtree.

      -v, --verbose
            Explain what is being moved to trash.

      -h, --help
            Print this help and exit.

    Examples:
      rip file.txt dir/              Move file.txt and dir/ to trash.
      rip -rfd path/                 rm-compatible recursive force trash.
      rip -u                         Pick a file to restore (interactive picker).
      rip -u /old/path/file.txt      Restore /old/path/file.txt directly.
      rip -u a b c                   Best-effort restore each path.
      rip -s                         List files trashed from the current dir.
      rip --empty-trash              Empty the trash (prompts for confirmation).
      rip --empty-trash --force      Empty the trash without prompting.
      rip -i file.txt                Inspect, then confirm before trashing.
      rip --graveyard /mnt/usb/.Trash  Use a custom trash location.

    Backend: trash-cli <https://github.com/andreafrancia/trash-cli>
    EOF
    }

    # trash-put cannot rename a mount point; shutil.move then falls back to
    # copy-and-delete, which empties the mount and discards the copy. trash-put
    # also moves a directory together with any mount inside it, and a later
    # trash-empty deletes through that mount. Trashing cannot skip a subtree the
    # way GNU rm --one-file-system does, so an operand holding a mount stays.
    # Sets KEPT to the operands that are safe to trash and PROTECT_STATUS to 1
    # when any was skipped.
    protect_operands() {
      KEPT=()
      PROTECT_STATUS=0
      local mountinfo op abs rest comp norm parent base canon enc prefix refusal mount_point
      local -a parts mount_points=()
      local -A parent_canon=() mount_set=()
      if ! mountinfo="$(< /proc/self/mountinfo)"; then
        echo "rip: cannot read /proc/self/mountinfo to protect mount points" >&2
        exit 1
      fi
      while read -r _ _ _ _ mount_point _; do
        mount_points+=("$mount_point")
        mount_set[$mount_point]=1
      done <<< "$mountinfo"
      for op in "$@"; do
        # trash-put reports an empty operand as nonexistent; normpath would turn it into ".".
        if [ -z "$op" ]; then
          KEPT+=("$op")
          continue
        fi
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
          KEPT+=("$op")
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
        if [ -n "''${parent_canon[$parent]+set}" ]; then
          canon="''${parent_canon[$parent]}"
        else
          # The trailing dot keeps newlines at the end of the path.
          if ! canon="$(cd -P -- "$parent" && pwd -P && echo .)"; then
            echo "rip: cannot resolve '$op' to check for mount points" >&2
            PROTECT_STATUS=1
            continue
          fi
          canon="''${canon%$'\n.'}"
          parent_canon[$parent]="$canon"
        fi
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
        if [ -n "''${mount_set[$enc]+set}" ]; then
          refusal="'$op' is a mount point, which trash-put cannot move intact"
        elif $ONE_FILE_SYSTEM; then
          for mount_point in "''${mount_points[@]}"; do
            case "$mount_point" in
              "$prefix"?*)
                refusal="mount point '$mount_point' lies inside '$op' (--one-file-system)"
                break
                ;;
            esac
          done
        fi
        if [ -n "$refusal" ]; then
          echo "rip: skipping '$op': $refusal" >&2
          PROTECT_STATUS=1
          continue
        fi
        KEPT+=("$op")
      done
    }

    # Parse a single short flag character. Called for each char in a
    # combined flag like -rfd.
    parse_short_flag() {
      case "$1" in
        h) usage; exit 0 ;;
        r|R|d) ;; # no-op: rm compat; trash-put handles dirs natively
        s) SEANCE=true ;;
        i) INSPECT=true ;;
        f) FORCE=true ;;
        v) VERBOSE=true ;;
        u) UNBURY=true ;;
        *) echo "rip: unknown option: -$1" >&2; exit 1 ;;
      esac
    }

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --help) usage; exit 0 ;;
        --empty-trash) EMPTY_TRASH=true; shift ;;
        --seance) SEANCE=true; shift ;;
        --unbury)
          UNBURY=true; shift
          while [[ $# -gt 0 ]] && [[ "$1" != -* ]]; do
            UNBURY_FILES+=("$1"); shift
          done ;;
        --inspect) INSPECT=true; shift ;;
        --force) FORCE=true; shift ;;
        --verbose) VERBOSE=true; shift ;;
        --recursive|--dir) shift ;;
        --one-file-system) ONE_FILE_SYSTEM=true; shift ;;
        --graveyard)
          TRASH_DIR_ARGS=(--trash-dir "''${2:?--graveyard requires an argument}")
          shift 2 ;;
        --graveyard=*)
          graveyard_val="''${1#*=}"
          if [[ -z "$graveyard_val" ]]; then
            echo "rip: --graveyard= requires a non-empty argument" >&2
            exit 1
          fi
          TRASH_DIR_ARGS=(--trash-dir "$graveyard_val")
          shift ;;
        --) shift; FILES+=("$@"); break ;;
        --*) echo "rip: unknown option: $1" >&2; exit 1 ;;
        -*)
          # Combined short flags: parse each character in sequence.
          combined="''${1#-}"
          shift
          while [[ -n "$combined" ]]; do
            flag="''${combined:0:1}"
            combined="''${combined:1}"
            parse_short_flag "$flag"
            # -u consumes remaining positional args as restore targets.
            if [[ "$flag" == u ]]; then
              while [[ $# -gt 0 ]] && [[ "$1" != -* ]]; do
                UNBURY_FILES+=("$1"); shift
              done
            fi
          done ;;
        *) FILES+=("$1"); shift ;;
      esac
    done

    # Modes are mutually exclusive: --empty-trash, -s/--seance,
    # -u/--unbury, and positional FILES may not be combined.
    mode_count=0
    mode_names=()
    $EMPTY_TRASH         && { mode_count=$(( mode_count + 1 )); mode_names+=(--empty-trash); }
    $SEANCE              && { mode_count=$(( mode_count + 1 )); mode_names+=(-s/--seance); }
    $UNBURY              && { mode_count=$(( mode_count + 1 )); mode_names+=(-u/--unbury); }
    (( ''${#FILES[@]} )) && { mode_count=$(( mode_count + 1 )); mode_names+=(FILES); }

    if (( mode_count > 1 )); then
      echo "rip: conflicting modes: ''${mode_names[*]}" >&2
      echo "rip: use exactly one operation per invocation; see rip --help" >&2
      exit 1
    fi

    if $EMPTY_TRASH; then
      if $FORCE; then
        trash-empty "''${TRASH_DIR_ARGS[@]}"
      else
        if [[ ! -t 0 ]]; then
          echo "rip: refusing to prompt with non-tty stdin; pass --force to confirm" >&2
          exit 1
        fi
        read -r -p "Permanently delete all trashed files? [y/N] " confirm
        if [[ "''${confirm,,}" == y ]]; then
          trash-empty "''${TRASH_DIR_ARGS[@]}"
        fi
      fi
      exit 0
    fi

    if $SEANCE; then
      # When invoked from the filesystem root, `pwd` returns `/` and
      # naive concatenation would search for `//` rather than `/`,
      # silently hiding every entry. Treat `/` as the special case
      # where the prefix is just one slash.
      seance_pwd="$(pwd)"
      if [[ "$seance_pwd" == "/" ]]; then
        seance_prefix="/"
      else
        seance_prefix="$seance_pwd/"
      fi
      trash-list "''${TRASH_DIR_ARGS[@]}" 2>/dev/null | grep -F " $seance_prefix" || true
      exit 0
    fi

    if $UNBURY; then
      if (( ''${#UNBURY_FILES[@]} == 0 )); then
        trash-restore "''${TRASH_DIR_ARGS[@]}"
        exit 0
      fi
      # `realpath -ms` mirrors `os.path.abspath` semantics used by
      # `trash-put` when it records `original_location`: normalise `.`
      # and `..` and tolerate missing components, but do not resolve
      # symlinks in parent components (so `/home -> /mnt/home` style
      # mounts still match the recorded path).
      unbury_rc=0
      for f in "''${UNBURY_FILES[@]}"; do
        rc=0
        trash-restore "''${TRASH_DIR_ARGS[@]}" -- "$(realpath -ms -- "$f")" || rc=$?
        # Preserve the first non-zero rc so the eventual exit status
        # matches the failure the operator is most likely debugging;
        # later failures are often cascades from the same root cause.
        if (( unbury_rc == 0 )); then
          unbury_rc=$rc
        fi
      done
      exit "$unbury_rc"
    fi

    if [[ ''${#FILES[@]} -eq 0 ]]; then
      usage; exit 1
    fi

    protect_operands "''${FILES[@]}"
    if (( ''${#KEPT[@]} == 0 )); then
      exit "$PROTECT_STATUS"
    fi

    if $INSPECT; then
      ls -la -- "''${KEPT[@]}"
      if ! $FORCE; then
        if [[ ! -t 0 ]]; then
          echo "rip: refusing to prompt with non-tty stdin; pass --force to confirm" >&2
          exit 1
        fi
        read -r -p "Bury these files? [y/N] " confirm
        [[ "''${confirm,,}" == y ]] || exit "$PROTECT_STATUS"
      fi
    fi

    TRASH_PUT_ARGS=()
    $FORCE && TRASH_PUT_ARGS+=(-f)
    $VERBOSE && TRASH_PUT_ARGS+=(-v)
    rc=0
    trash-put "''${TRASH_PUT_ARGS[@]}" "''${TRASH_DIR_ARGS[@]}" -- "''${KEPT[@]}" || rc=$?
    if (( PROTECT_STATUS != 0 )); then
      exit "$PROTECT_STATUS"
    fi
    exit "$rc"
  '';
}
