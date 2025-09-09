{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages.generation-manager = pkgs.writeShellApplication {
        name = "generation-manager";
        runtimeInputs = with pkgs; [
          nix
          coreutils
          jq
          nixos-rebuild
          gnugrep
          gawk
        ];
        text = ''
                  set -euo pipefail

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
                    local cmd="$1"
                    if [ "$DRY_RUN" = "true" ]; then
                      echo -e "''${YELLOW}[DRY RUN]''${NC} Would execute: $cmd"
                    else
                      eval "$cmd"
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
                  for arg in "$@"; do
                    case "$arg" in
                      -v|--verbose)
                        VERBOSE="true"
                        shift
                        ;;
                    esac
                  done

                  case "''${1:-help}" in
                    list)
                      echo -e "''${BLUE}System generations:''${NC}"
                      nix-env --list-generations -p /nix/var/nix/profiles/system
                      ;;

                    current)
                      echo -e "''${BLUE}Current generation:''${NC}"
                      current_gen=$(readlink /nix/var/nix/profiles/system | sed 's/.*-\([0-9]*\)-link/\1/')
                      echo "Generation: $current_gen"
                      echo "Profile: $(readlink /nix/var/nix/profiles/system)"
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
                      execute_cmd "nix-env --delete-generations +$keep -p /nix/var/nix/profiles/system"
                      ;;

                    gc)
                      echo -e "''${YELLOW}Running garbage collection...''${NC}"
                      execute_cmd "nix-collect-garbage -d"
                      if [ "$DRY_RUN" = "false" ]; then
                        echo -e "''${YELLOW}Running system garbage collection...''${NC}"
                        sudo nix-collect-garbage -d
                      else
                        echo -e "''${YELLOW}[DRY RUN]''${NC} Would execute: sudo nix-collect-garbage -d"
                      fi
                      ;;

                    switch)
                      if [ -z "''${2:-}" ]; then
                        echo -e "''${RED}Error: Host name required''${NC}"
                        exit 1
                      fi
                      echo -e "''${YELLOW}Switching to configuration for host: $2''${NC}"
                      execute_cmd "nixos-rebuild switch --flake .#$2"
                      ;;

                    rollback)
                      gens="''${2:-1}"
                      echo -e "''${YELLOW}Rolling back $gens generation(s)...''${NC}"
                      for _ in $(seq 1 "$gens"); do
                        execute_cmd "nixos-rebuild switch --rollback"
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
                      MAX_SCORE=35

                      echo -e "\n''${YELLOW}Checking compliance metrics:''${NC}"

                      # Check for literal path imports (20 points)
                      echo -n "1. No literal path imports: "
                      if [ -d modules ]; then
                        # Enhanced pattern to catch actual file path imports
                        # Matches: ./file, ../file, /absolute/path
                        literal_imports=$(grep -Hn -E '^[[:space:]]*imports[[:space:]]*=' modules/ -r 2>/dev/null | \
                          grep -E '\./|\.\./' | \
                          grep -v '# ' | grep -v '//' || true)
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
                        todo_list=$(grep -Hn "TODO" modules/ -r 2>/dev/null | grep -v "generation-manager.nix" || true)
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

                      # Check nvidia-gpu specialisation (15 points)
                      echo -n "3. nvidia-gpu has specialisation: "
                      if [ -f modules/nvidia-gpu.nix ]; then
                        if grep -q "specialisation" modules/nvidia-gpu.nix 2>/dev/null; then
                          echo -e "''${GREEN}✓ (15/15)''${NC}"
                          SCORE=$((SCORE + 15))
                        else
                          echo -e "''${RED}✗ (0/15)''${NC}"
                        fi
                      else
                        echo -e "''${YELLOW}? nvidia-gpu.nix not found''${NC}"
                      fi

                      echo -e "\n''${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━''${NC}"
                      echo -e "''${BLUE}Dendritic Pattern Compliance:''${NC} ''${YELLOW}''${SCORE}/''${MAX_SCORE}''${NC}"

                      if [ $SCORE -eq $MAX_SCORE ]; then
                        echo -e "''${GREEN}✅ PERFECT COMPLIANCE!''${NC}"
                      elif [ $((SCORE * 100 / MAX_SCORE)) -ge 90 ]; then
                        echo -e "''${GREEN}✅ Excellent compliance!''${NC}"
                      elif [ $((SCORE * 100 / MAX_SCORE)) -ge 70 ]; then
                        echo -e "''${YELLOW}⚠ Good progress, improvements needed''${NC}"
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
    };

  # Make generation-manager available in user environments
  flake.homeManagerModules.base =
    { pkgs, ... }:
    {
      home.packages = [ config.flake.packages.${pkgs.system}.generation-manager ];
    };
}
