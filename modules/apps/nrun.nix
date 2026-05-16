/*
  Package: nrun
  Description: Run nixpkgs packages with unfree packages allowed by default.
  Homepage: nil
  Documentation: https://nix.dev/manual/nix/latest/command-ref/new-cli/nix3-run
  Repository: https://github.com/Bad3r/nixos

  Summary:
    * Runs a package from the configured nixpkgs flake using `nix run`.
    * Enables unfree package evaluation by default for one-off invocations.

  Options:
    -h: Show usage information.
    --help: Show usage information.
    --: Stop option parsing and treat the next argument as the package attribute.
    <nixpkgs-attr>: Run `nixpkgs#<nixpkgs-attr>` and pass remaining arguments through.

  Notes:
    * Sets `NIXPKGS_ALLOW_UNFREE=1` only when the caller has not set it.
    * Uses `--impure` because nixpkgs reads `NIXPKGS_ALLOW_UNFREE` from the environment.
*/
_:
let
  NrunModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.nrun.extended;

      nrunWrapper = pkgs.writeShellApplication {
        name = "nrun";
        runtimeInputs = [ config.nix.package ];
        text = ''
          usage() {
            cat <<'EOF'
          nrun - run a nixpkgs package with unfree packages allowed

          Usage:
            nrun [--] <nixpkgs-attr> [args...]

          Options:
            -h, --help  Show this help and exit.
            --          Stop option parsing.

          Environment:
            NIXPKGS_ALLOW_UNFREE defaults to 1 when unset.
          EOF
          }

          if [[ $# -eq 0 ]]; then
            usage >&2
            exit 2
          fi

          case "$1" in
            -h|--help)
              usage
              exit 0
              ;;
            --)
              shift
              if [[ $# -eq 0 ]]; then
                usage >&2
                exit 2
              fi
              ;;
            -*)
              echo "nrun: unknown option: $1" >&2
              usage >&2
              exit 2
              ;;
          esac

          pkg="$1"
          shift

          export NIXPKGS_ALLOW_UNFREE="''${NIXPKGS_ALLOW_UNFREE:-1}"
          exec nix run --impure "nixpkgs#$pkg" -- "$@"
        '';
      };
    in
    {
      options.programs.nrun.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable the nrun nixpkgs runner wrapper.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = nrunWrapper;
          defaultText = lib.literalExpression "pkgs.writeShellApplication { name = \"nrun\"; ... }";
          description = "Derivation providing the nrun wrapper.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.nrun = NrunModule;
}
