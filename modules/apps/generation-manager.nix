/*
  Package: generation-manager
  Description: Manage NixOS generations.
  Homepage: nil
  Documentation: docs/architecture/06-reference.md
  Repository: https://github.com/Bad3r/nixos

  Summary:
    * Lists, cleans, rolls back, diffs, and inspects NixOS system generations.

  Options:
    list: List all system generations.
    clean [N]: Keep only N most recent generations.
    switch <host>: Switch to a host configuration.
    rollback [N]: Roll back N generations.
    diff <g1> <g2>: Compare two generations.
    current: Show current generation information.
    gc: Garbage collect after cleaning.
    info <gen>: Show detailed information about a generation.

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
          ''${GREEN}info <gen>''${NC}        Show detailed info about a generation

        Environment:
          ''${YELLOW}DRY_RUN=true''${NC}      Show what would be done without doing it
        HELP
                }

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
