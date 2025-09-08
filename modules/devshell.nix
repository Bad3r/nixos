{ inputs, ... }:
{
  imports = [
    inputs.treefmt-nix.flakeModule
    inputs.make-shell.flakeModules.default
  ];
  perSystem =
    psArgs@{ pkgs, config, ... }:
    {
      # Use make-shells pattern for better modularity
      make-shells.default = {
        packages =
          with pkgs;
          let
            inputBranchesCatalog = pkgs.writeShellApplication {
              name = "input-branches-catalog";
              text = ''
                set -euo pipefail
                # Find input-branches commands in PATH
                found=$(
                  IFS=:
                  for d in $PATH; do
                    ls -1 "$d"/input-branches-* "$d"/input-branch-* 2>/dev/null || true
                  done | awk 'NF' | sort -u
                )
                if [ -z "''${found}" ]; then
                  echo "No input-branches commands found in PATH."
                  echo "If you expect them, enable the input-branches module and add its commands to the dev shell."
                  exit 0
                fi
                echo "Input-branches command catalog:";
                echo "''${found}"
              '';
            };
          in
          [
            nixfmt-rfc-style
            nil # Nix LSP
            nix-tree
            nix-diff
            act
            jq
            yq
            inputBranchesCatalog
            config.packages.generation-manager
            config.treefmt.build.wrapper
          ]
          ++ (if psArgs.config ? input-branches then psArgs.config.input-branches.commands.all else [ ]);

        inputsFrom = [ config.pre-commit.devShell ];

        shellHook = ''
          echo "🚀 NixOS Configuration Development Shell"
          echo ""
          echo "Available commands:"
          echo "  nix flake check        - Validate the flake"
          echo "  nix fmt                - Format Nix files"
          echo "  pre-commit install     - Install git hooks"
          echo "  pre-commit run         - Run hooks on staged files"
          echo "  input-branches-catalog - List input-branches commands (if available)"
          echo "  write-files            - Generate managed files (README.md)"
          echo ""
          ${config.pre-commit.installationScript}
        '';
      };

      # Configure treefmt
      treefmt = {
        projectRootFile = "flake.nix";
        programs = {
          nixfmt.enable = true;
          prettier.enable = true;
          shfmt.enable = true;
        };
      };
    };
}
