/*
  Package: generation-manager
  Description: Manage NixOS generations and score Dendritic Pattern compliance.
  Homepage: nil
  Documentation: docs/architecture/06-reference.md
  Repository: https://github.com/Bad3r/nixos

  Summary:
    * Lists, cleans, rolls back, diffs, and inspects NixOS system generations.
    * Scores Dendritic Pattern compliance for this repository.

  Options:
    list: List all system generations.
    clean [N]: Keep only N most recent generations.
    switch <host>: Switch to a host configuration.
    rollback [N]: Roll back N generations.
    diff <g1> <g2>: Compare two generations.
    current: Show current generation information.
    gc: Garbage collect after cleaning.
    score: Calculate Dendritic Pattern compliance score.
    info <gen>: Show detailed information about a generation.
    -v, --verbose: Show detailed score violations.

  Notes:
    * The flake package output is retained for `nix run .#generation-manager -- ...`.
    * `nix-diff` remains optional and is used only when present on PATH.
    * `sudo` is intentionally resolved from the runtime environment.
*/
_:
let
  mkGenerationManagerPackage =
    pkgs:
    pkgs.writeShellApplication {
      name = "generation-manager";
      runtimeInputs = with pkgs; [
        nix
        coreutils
        jq
        nixos-rebuild
        gnugrep
        gawk
        gnused
        diffutils
        findutils
      ];
      text = /* bash */ ''
                set -euo pipefail
                export LC_ALL=C

                # Dry run support
                DRY_RUN="''${DRY_RUN:-false}"

                # Verbose output support
                VERBOSE="''${VERBOSE:-false}"

                # Color codes for output
                RED='\033[0;31m'
                GREEN='\033[0;32m'
                YELLOW='\033[1;33m'
                BLUE='\033[0;34m'
                NC='\033[0m' # No Color

                execute_cmd() {
                  if [ "$DRY_RUN" = "true" ]; then
                    printf "%b[DRY RUN]%b Would execute:" "$YELLOW" "$NC"
                    printf " %q" "$@"
                    printf "\n"
                  else
                    "$@"
                  fi
                }

                print_help() {
                  cat <<HELP
        ''${BLUE}Generation Manager - NixOS generation management tool''${NC}

        Usage: generation-manager [options] <command> [args]

        Commands:
          ''${GREEN}list''${NC}              List all system generations
          ''${GREEN}clean [N]''${NC}         Keep only N most recent generations (default: 5)
          ''${GREEN}switch <host>''${NC}     Switch to configuration for host
          ''${GREEN}rollback [N]''${NC}      Rollback N generations (default: 1)
          ''${GREEN}diff <g1> <g2>''${NC}    Compare two generations
          ''${GREEN}current''${NC}           Show current generation info
          ''${GREEN}gc''${NC}                Garbage collect after cleaning
          ''${GREEN}score''${NC}             Calculate Dendritic Pattern compliance score
          ''${GREEN}info <gen>''${NC}        Show detailed info about a generation

        Options:
          ''${GREEN}-v, --verbose''${NC}     Show detailed output for violations in score

        Environment:
          ''${YELLOW}DRY_RUN=true''${NC}      Show what would be done without doing it
          ''${YELLOW}VERBOSE=true''${NC}      Same as -v flag
        HELP
                }

                # Handle verbose flag
                args=()
                while [ $# -gt 0 ]; do
                  case "$1" in
                    -v|--verbose)
                      VERBOSE="true"
                      shift
                      ;;
                    *)
                      args+=("$1")
                      shift
                      ;;
                  esac
                done
                set -- "''${args[@]}"

                case "''${1:-help}" in
                  list)
                    echo -e "''${BLUE}System generations:''${NC}"
                    nix-env --list-generations -p /nix/var/nix/profiles/system
                    ;;

                  current)
                    echo -e "''${BLUE}Current generation:''${NC}"
                    current_path=$(readlink /nix/var/nix/profiles/system)
                    current_gen="''${current_path%-link}"
                    current_gen="''${current_gen##*-}"
                    echo "Generation: $current_gen"
                    echo "Profile: $current_path"
                    echo "Date: $(stat -c %y /nix/var/nix/profiles/system | cut -d' ' -f1,2)"
                    ;;

                  info)
                    if [ -z "''${2:-}" ]; then
                      echo -e "''${RED}Error: Generation number required''${NC}"
                      exit 1
                    fi
                    gen_path="/nix/var/nix/profiles/system-$2-link"
                    if [ ! -e "$gen_path" ]; then
                      echo -e "''${RED}Error: Generation $2 does not exist''${NC}"
                      exit 1
                    fi
                    echo -e "''${BLUE}Generation $2 Information:''${NC}"
                    echo "Path: $gen_path"
                    echo "Date: $(stat -c %y "$gen_path" | cut -d' ' -f1,2)"
                    echo "Kernel: $(readlink "$gen_path/kernel" | xargs basename)"
                    echo "NixOS Version: $(cat "$gen_path/nixos-version" 2>/dev/null || echo "Unknown")"
                    ;;

                  clean)
                    keep="''${2:-5}"
                    echo -e "''${YELLOW}Keeping $keep most recent generations...''${NC}"
                    execute_cmd sudo nix-env --delete-generations "+$keep" -p /nix/var/nix/profiles/system
                    ;;

                  gc)
                    echo -e "''${YELLOW}Running garbage collection...''${NC}"
                    execute_cmd nix-collect-garbage -d
                    echo -e "''${YELLOW}Running system garbage collection...''${NC}"
                    execute_cmd sudo nix-collect-garbage -d
                    ;;

                  switch)
                    if [ -z "''${2:-}" ]; then
                      echo -e "''${RED}Error: Host name required''${NC}"
                      exit 1
                    fi
                    echo -e "''${YELLOW}Switching to configuration for host: $2''${NC}"
                    execute_cmd sudo nixos-rebuild switch --flake ".#$2"
                    ;;

                  rollback)
                    gens="''${2:-1}"
                    echo -e "''${YELLOW}Rolling back $gens generation(s)...''${NC}"
                    for _ in $(seq 1 "$gens"); do
                      execute_cmd sudo nixos-rebuild switch --rollback
                    done
                    ;;

                  diff)
                    if [ -z "''${2:-}" ] || [ -z "''${3:-}" ]; then
                      echo -e "''${RED}Usage: generation-manager diff <gen1> <gen2>''${NC}"
                      exit 1
                    fi
                    gen1="/nix/var/nix/profiles/system-$2-link"
                    gen2="/nix/var/nix/profiles/system-$3-link"

                    if [ ! -e "$gen1" ]; then
                      echo -e "''${RED}Error: Generation $2 does not exist''${NC}"
                      exit 1
                    fi
                    if [ ! -e "$gen2" ]; then
                      echo -e "''${RED}Error: Generation $3 does not exist''${NC}"
                      exit 1
                    fi

                    echo -e "''${BLUE}Comparing generation $2 with $3:''${NC}"
                    if command -v nix-diff >/dev/null 2>&1; then
                      nix-diff "$gen1" "$gen2"
                    else
                      echo -e "''${YELLOW}nix-diff not installed, showing basic diff...''${NC}"
                      diff -u <(nix-store -qR "$gen1" | sort) <(nix-store -qR "$gen2" | sort) || true
                    fi
                    ;;

                  score)
                    echo -e "''${BLUE}Calculating Dendritic Pattern compliance score...''${NC}"
                    SCORE=0
                    MAX_SCORE=20

                    echo -e "\n''${YELLOW}Checking compliance metrics:''${NC}"

                    # Check for literal path imports (20 points)
                    echo -n "1. No literal path imports: "
                    if [ -d modules ]; then
                      # Track imports = [ ... ] blocks across lines so the
                      # idiomatic multi-line style is caught too; the previous
                      # single-line grep only flagged ./ on the imports line
                      # itself and missed every path on a following line.
                      # Paths with any segment starting with "_" are outside
                      # import-tree discovery (hasInfix "/_"), so importing
                      # them literally is the sanctioned pattern; exempt them.
                      # shellcheck disable=SC2016
                      literal_imports=$(find modules/ -name '*.nix' -print0 2>/dev/null | \
                        xargs -0 -r awk '
                          FNR == 1 { inblock = 0; depth = 0 }
                          {
                            line = $0
                            sub(/#.*/, "", line)
                            if (!inblock && line ~ /^[[:space:]]*imports[[:space:]]*=/) {
                              inblock = 1
                              depth = 0
                            }
                            if (inblock) {
                              tmp = line
                              while (match(tmp, "\\.\\.?/[A-Za-z0-9_./-]+")) {
                                p = substr(tmp, RSTART, RLENGTH)
                                n = split(p, parts, "/")
                                exempt = 0
                                for (i = 1; i <= n; i++) {
                                  if (substr(parts[i], 1, 1) == "_") {
                                    exempt = 1
                                    break
                                  }
                                }
                                if (!exempt) {
                                  printf "%s:%d:%s\n", FILENAME, FNR, $0
                                  break
                                }
                                tmp = substr(tmp, RSTART + RLENGTH)
                              }
                              depth += gsub(/\[/, "", line)
                              depth -= gsub(/\]/, "", line)
                              if (depth <= 0 && line ~ /;/) inblock = 0
                            }
                          }
                        ' || true)
                      if [ -z "$literal_imports" ]; then
                        import_count=0
                      else
                        import_count=$(echo "$literal_imports" | wc -l)
                      fi

                      if [ "$import_count" -eq 0 ] || [ -z "$literal_imports" ]; then
                        echo -e "''${GREEN}✓ (20/20)''${NC}"
                        SCORE=$((SCORE + 20))
                      else
                        echo -e "''${RED}✗ (0/20) - Found $import_count violations''${NC}"
                        if [ "$VERBOSE" = "true" ] && [ -n "$literal_imports" ]; then
                          echo -e "''${RED}  Violations found:''${NC}"
                          echo "$literal_imports" | while IFS=: read -r file line content; do
                            echo -e "    ''${YELLOW}$file:$line''${NC}: $content"
                          done
                        fi
                      fi
                    else
                      echo -e "''${YELLOW}? modules directory not found''${NC}"
                    fi

                    # Check TODOs (warning only, no points)
                    echo -n "2. TODO Comments: "
                    if [ -d modules ]; then
                      todo_list=$(grep -Hn -r --exclude=generation-manager.nix "TODO" modules/ 2>/dev/null || true)
                      if [ -z "$todo_list" ]; then
                        todo_count=0
                      else
                        todo_count=$(echo "$todo_list" | wc -l)
                      fi

                      if [ "$todo_count" -eq 0 ] || [ -z "$todo_list" ]; then
                        echo -e "''${GREEN}✓ None found''${NC}"
                      else
                        echo -e "''${YELLOW}⚠ $todo_count reminder(s) found''${NC}"
                        # Print each TODO as: path:line TODO: ...
                        echo "$todo_list" | while IFS=: read -r file line content; do
                          todo_text=$(printf "%s" "$content" | sed -E 's/.*(TODO.*)/\1/')
                          echo "$file:$line $todo_text"
                        done
                      fi
                    fi

                    echo -e "\n''${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━''${NC}"
                    echo -e "''${BLUE}Dendritic Pattern Compliance:''${NC} ''${YELLOW}''${SCORE}/''${MAX_SCORE}''${NC}"

                    if [ $SCORE -eq $MAX_SCORE ]; then
                      echo -e "''${GREEN}✅ PERFECT COMPLIANCE!''${NC}"
                    else
                      echo -e "''${RED}❌ Significant improvements required''${NC}"
                    fi
                    ;;

                  help|--help|-h)
                    print_help
                    ;;

                  *)
                    echo -e "''${RED}Unknown command: $1''${NC}"
                    print_help
                    exit 1
                    ;;
                esac
      '';
    };

  GenerationManagerModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."generation-manager".extended;
    in
    {
      options.programs."generation-manager".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable generation-manager.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = mkGenerationManagerPackage pkgs;
          defaultText = lib.literalExpression "pkgs.writeShellApplication { name = \"generation-manager\"; ... }";
          description = "Derivation providing the generation-manager wrapper.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  perSystem =
    { pkgs, ... }:
    {
      packages.generation-manager = mkGenerationManagerPackage pkgs;
    };

  flake.nixosModules.apps."generation-manager" = GenerationManagerModule;
}
