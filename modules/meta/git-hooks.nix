{ inputs, ... }:
{
  imports = [ inputs.git-hooks.flakeModule ];
  perSystem =
    { pkgs, ... }:
    {
      pre-commit = {
        check.enable = true;
        settings = {
          hooks = {
            # Nix-specific hooks
            nixfmt-rfc-style.enable = true;
            # Avoid scanning vendored inputs and large local docs
            deadnix = {
              enable = true;
              excludes = [
                "^inputs/"
                "^nixos_docs_md/"
              ];
            };
            statix =
              let
                statixWrapper = pkgs.writeShellApplication {
                  name = "statix-precommit-wrapper";
                  runtimeInputs = [
                    pkgs.statix
                    pkgs.coreutils
                  ];
                  text = ''
                    set -euo pipefail
                    status=0
                    if [ "$#" -eq 0 ]; then
                      # Fallback to repository root
                      statix check --format errfmt || status=$?
                      exit $status
                    fi
                    for f in "$@"; do
                      # Only run on existing files
                      if [ -f "$f" ]; then
                        statix check --format errfmt -- "$f" || status=$?
                      fi
                    done
                    exit $status
                  '';
                };
              in
              {
                enable = true;
                excludes = [
                  "^inputs/"
                  "^nixos_docs_md/"
                ];
                entry = "${statixWrapper}/bin/statix-precommit-wrapper";
                pass_filenames = true;
              };
            # flake-checker not used: we rely on
            # `nix flake check` and pre-push submodule checks

            # Shell script quality
            shellcheck.enable = true;

            # Documentation and text quality
            typos.enable = true;
            trim-trailing-whitespace.enable = true;

            # Security
            detect-private-keys.enable = true;
            ripsecrets = {
              enable = true;
              excludes = [
                "nixos_docs_md/.*\\.md$" # Documentation files with examples
                "modules/networking/networking.nix" # Contains public minisign key
              ];
            };

            # Config file validation
            check-yaml.enable = true;
            check-json.enable = true;
          };
        };
      };
    };
}
