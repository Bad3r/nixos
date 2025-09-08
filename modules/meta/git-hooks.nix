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
            flake-checker =
              let
                wrapper = pkgs.writeShellApplication {
                  name = "flake-checker-local-aware";
                  runtimeInputs = [
                    pkgs.jq
                    pkgs.coreutils
                    pkgs.flake-checker
                  ];
                  text = ''
                    set -euo pipefail
                    # Skip when nixpkgs input is a local path (input-branches mirror)
                    if [ -f flake.lock ] && jq -e '.nodes.nixpkgs.locked.type == "path"' < flake.lock >/dev/null 2>&1; then
                      echo "flake-checker: skipped (nixpkgs is a local path input)"
                      exit 0
                    fi
                    exec flake-checker "$@"
                  '';
                };
              in
              {
                enable = true;
                excludes = [
                  "^inputs/"
                  "^nixos_docs_md/"
                ];
                entry = "${wrapper}/bin/flake-checker-local-aware";
                pass_filenames = false;
              };

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
