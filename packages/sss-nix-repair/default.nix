{
  lib,
  writeShellApplication,
  nh,
  nix,
  coreutils,
  findutils,
  gnugrep,
  gnused,
  gawk,
}:

writeShellApplication {
  name = "sss-nix-repair";

  runtimeInputs = [
    nh
    nix
    coreutils
    findutils
    gnugrep
    gnused
    gawk
  ];

  text = /* sh */ ''
        KEEP_SINCE="14d"
        KEEP_COUNT="3"
        RUN_CLEAN=1
        RUN_VERIFY=1
        TRUST_VERIFY=0
        AUTO_YES=0
        DRY_RUN=0

        usage() {
          cat <<'EOF'
    Usage: sss-nix-repair [OPTIONS]

    Maintenance and repair helper for Nix store/profile corruption.

    Options:
      --keep-since <duration>  Retention window for nh clean (default: 14d)
      --keep <count>           Minimum generations kept by nh clean (default: 3)
      --no-clean               Skip nh clean phase
      --no-verify              Skip nix store verify phase
      --trust                  Include trust/signature checks in verify
      --yes                    Auto-approve generation deletion prompts
      --dry-run                Print mutating commands without executing them
      -h, --help               Show this help
    EOF
        }

        log() {
          printf '%s\n' "$*"
        }

        warn() {
          printf 'WARN: %s\n' "$*" >&2
        }

        run_cmd() {
          if [ "$DRY_RUN" -eq 1 ]; then
            printf '[dry-run] '
            printf '%s ' "$@"
            printf '\n'
            return 0
          fi

          "$@"
        }

        confirm() {
          prompt="$1"

          if [ "$AUTO_YES" -eq 1 ]; then
            return 0
          fi

          printf '%s [y/N] ' "$prompt"
          read -r answer || return 1

          case "$answer" in
            y | Y | yes | YES | Yes) return 0 ;;
            *) return 1 ;;
          esac
        }

        while [ "$#" -gt 0 ]; do
          case "$1" in
            --keep-since)
              shift
              [ "$#" -gt 0 ] || {
                warn "--keep-since requires a value"
                usage
                exit 2
              }
              KEEP_SINCE="$1"
              ;;
            --keep)
              shift
              [ "$#" -gt 0 ] || {
                warn "--keep requires a value"
                usage
                exit 2
              }
              KEEP_COUNT="$1"
              ;;
            --no-clean) RUN_CLEAN=0 ;;
            --no-verify) RUN_VERIFY=0 ;;
            --trust) TRUST_VERIFY=1 ;;
            --yes) AUTO_YES=1 ;;
            --dry-run) DRY_RUN=1 ;;
            -h | --help)
              usage
              exit 0
              ;;
            *)
              warn "Unknown argument: $1"
              usage
              exit 2
              ;;
          esac
          shift
        done

        TMP_DIR="$(mktemp -d "''${TMPDIR:-/tmp}/sss-nix-repair.XXXXXX")" || {
          warn "Failed to create temporary directory"
          exit 1
        }

        VERIFY_LOG="$TMP_DIR/verify.log"
        BAD_PATHS="$TMP_DIR/bad-paths.txt"
        USER_GENS="$TMP_DIR/user-generations.txt"
        SYSTEM_GENS="$TMP_DIR/system-generations.txt"
        ALL_USER_GENS="$TMP_DIR/all-user-generations.txt"
        ALL_SYSTEM_GENS="$TMP_DIR/all-system-generations.txt"
        USER_DELETE_FILE="$TMP_DIR/user-delete.txt"
        SYSTEM_DELETE_FILE="$TMP_DIR/system-delete.txt"
        ROOTS_TMP="$TMP_DIR/roots.txt"

        # shellcheck disable=SC2329
        cleanup() {
          rm -f "$VERIFY_LOG" "$BAD_PATHS" "$USER_GENS" "$SYSTEM_GENS" "$ALL_USER_GENS" "$ALL_SYSTEM_GENS" "$USER_DELETE_FILE" "$SYSTEM_DELETE_FILE" "$ROOTS_TMP"
          rmdir "$TMP_DIR" 2>/dev/null || true
        }

        trap cleanup EXIT INT TERM HUP

        : > "$BAD_PATHS"
        : > "$USER_GENS"
        : > "$SYSTEM_GENS"
        : > "$USER_DELETE_FILE"
        : > "$SYSTEM_DELETE_FILE"

        OVERALL_RC=0
        VERIFY_RC=0
        DELETED_ANY=0

        if [ "$RUN_CLEAN" -eq 1 ]; then
          log ":: Running nh clean"
          if ! run_cmd nh clean all --keep-since "$KEEP_SINCE" --keep "$KEEP_COUNT"; then
            CLEAN_RC=$?
            warn "nh clean failed with exit code $CLEAN_RC"
            OVERALL_RC=$CLEAN_RC
          fi
        else
          log ":: Skipping nh clean (--no-clean)"
        fi

        if [ "$RUN_VERIFY" -eq 1 ]; then
          log ":: Running nix store verify"
          if [ "$DRY_RUN" -eq 1 ]; then
            if [ "$TRUST_VERIFY" -eq 1 ]; then
              run_cmd sudo nix store verify --all --repair
            else
              run_cmd sudo nix store verify --all --repair --no-trust
            fi
          else
            if [ "$TRUST_VERIFY" -eq 1 ]; then
              # shellcheck disable=SC2024
              sudo nix store verify --all --repair >"$VERIFY_LOG" 2>&1
            else
              # shellcheck disable=SC2024
              sudo nix store verify --all --repair --no-trust >"$VERIFY_LOG" 2>&1
            fi
            VERIFY_RC=$?
            cat "$VERIFY_LOG"
          fi
        else
          log ":: Skipping nix store verify (--no-verify)"
        fi

        if [ "$RUN_VERIFY" -eq 1 ] && [ "$DRY_RUN" -eq 0 ] && [ -s "$VERIFY_LOG" ]; then
          sed -n "s/.*path '\\([^']*\\)'.*/\\1/p" "$VERIFY_LOG" | sort -u > "$BAD_PATHS"
        fi

        if [ -s "$BAD_PATHS" ]; then
          log ":: Corrupted store paths"
          while IFS= read -r store_path; do
            [ -n "$store_path" ] || continue
            printf '  %s\n' "$store_path"
            nix-store -q --roots "$store_path" >"$ROOTS_TMP" 2>/dev/null || true

            if [ -s "$ROOTS_TMP" ]; then
              sed -n 's/.*profile-\([0-9][0-9]*\)-link.*/\1/p' "$ROOTS_TMP" >> "$USER_GENS"
              sed -n 's/.*system-\([0-9][0-9]*\)-link.*/\1/p' "$ROOTS_TMP" >> "$SYSTEM_GENS"
              grep -E 'profile-[0-9]+-link|system-[0-9]+-link' "$ROOTS_TMP" | sed 's/^/    root: /' || true
            else
              warn "No roots found for $store_path"
            fi
          done < "$BAD_PATHS"
          sort -u -o "$USER_GENS" "$USER_GENS"
          sort -u -o "$SYSTEM_GENS" "$SYSTEM_GENS"
        else
          log ":: No corrupted paths detected in verify output"
        fi

        USER_PROFILE="$HOME/.local/state/nix/profiles/profile"

        log ":: User profile generations"
        if [ -e "$USER_PROFILE" ]; then
          if nix-env -p "$USER_PROFILE" --list-generations >"$ALL_USER_GENS" 2>/dev/null; then
            cat "$ALL_USER_GENS"
          else
            warn "Failed to list user generations"
            : > "$ALL_USER_GENS"
          fi
        else
          warn "User profile not found at $USER_PROFILE"
          : > "$ALL_USER_GENS"
        fi

        log ":: System profile generations"
        # shellcheck disable=SC2024
        if sudo nix-env -p /nix/var/nix/profiles/system --list-generations >"$ALL_SYSTEM_GENS" 2>/dev/null; then
          cat "$ALL_SYSTEM_GENS"
        else
          warn "Failed to list system generations (sudo may be required)"
          : > "$ALL_SYSTEM_GENS"
        fi

        if [ -s "$USER_GENS" ]; then
          USER_CURRENT="$(awk '/\(current\)/ { print $1; exit }' "$ALL_USER_GENS")"
          : > "$USER_DELETE_FILE"
          while IFS= read -r gen; do
            [ -n "$gen" ] || continue
            if [ "$gen" = "$USER_CURRENT" ]; then
              warn "Skipping current user generation $gen"
            else
              printf '%s\n' "$gen" >> "$USER_DELETE_FILE"
            fi
          done < "$USER_GENS"

          if [ -s "$USER_DELETE_FILE" ]; then
            USER_DELETE_LIST="$(tr '\n' ' ' < "$USER_DELETE_FILE" | sed 's/[[:space:]]*$//')"
            log ":: Corrupted user generations: $USER_DELETE_LIST"
            if confirm "Delete corrupted non-current user generations?"; then
              while IFS= read -r delete_gen; do
                [ -n "$delete_gen" ] || continue
                if run_cmd nix-env -p "$USER_PROFILE" --delete-generations "$delete_gen"; then
                  DELETED_ANY=1
                else
                  warn "Failed deleting user generation $delete_gen"
                  OVERALL_RC=1
                fi
              done < "$USER_DELETE_FILE"
            fi
          fi
        fi

        if [ -s "$SYSTEM_GENS" ]; then
          SYSTEM_CURRENT="$(awk '/\(current\)/ { print $1; exit }' "$ALL_SYSTEM_GENS")"
          : > "$SYSTEM_DELETE_FILE"
          while IFS= read -r gen; do
            [ -n "$gen" ] || continue
            if [ "$gen" = "$SYSTEM_CURRENT" ]; then
              warn "Skipping current system generation $gen"
            else
              printf '%s\n' "$gen" >> "$SYSTEM_DELETE_FILE"
            fi
          done < "$SYSTEM_GENS"

          if [ -s "$SYSTEM_DELETE_FILE" ]; then
            SYSTEM_DELETE_LIST="$(tr '\n' ' ' < "$SYSTEM_DELETE_FILE" | sed 's/[[:space:]]*$//')"
            log ":: Corrupted system generations: $SYSTEM_DELETE_LIST"
            if confirm "Delete corrupted non-current system generations?"; then
              while IFS= read -r delete_gen; do
                [ -n "$delete_gen" ] || continue
                if run_cmd sudo nix-env -p /nix/var/nix/profiles/system --delete-generations "$delete_gen"; then
                  DELETED_ANY=1
                else
                  warn "Failed deleting system generation $delete_gen"
                  OVERALL_RC=1
                fi
              done < "$SYSTEM_DELETE_FILE"
            fi
          fi
        fi

        if [ "$DELETED_ANY" -eq 1 ]; then
          log ":: Running nix store gc"
          if ! run_cmd sudo nix store gc; then
            warn "nix store gc failed"
            OVERALL_RC=1
          fi
        fi

        if [ "$VERIFY_RC" -ne 0 ]; then
          OVERALL_RC="$VERIFY_RC"
          warn "nix store verify returned non-zero exit code: $VERIFY_RC"
        fi

        if [ "$OVERALL_RC" -eq 0 ]; then
          log "INFO: sss-nix-repair completed successfully"
        else
          warn "sss-nix-repair completed with issues (exit code $OVERALL_RC)"
        fi

        exit "$OVERALL_RC"
  '';

  meta = {
    description = "Guided Nix store repair workflow with generation triage and optional cleanup";
    homepage = "https://github.com/vx/nixos";
    license = lib.licenses.mit;
    mainProgram = "sss-nix-repair";
    platforms = lib.platforms.linux;
  };
}
