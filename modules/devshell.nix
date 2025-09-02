{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];
  perSystem =
    { pkgs, config, ... }:
    {
      devShells.default = pkgs.mkShell {
        packages = with pkgs; [
          nixfmt-rfc-style
          nil # Nix LSP
          nix-tree
          nix-diff
          jq
          yq
          config.treefmt.build.wrapper
        ];

        inputsFrom = [ config.pre-commit.devShell ];

        shellHook = ''
          echo "🚀 NixOS Configuration Development Shell"
          echo ""
          echo "Available commands:"
          echo "  nix flake check    - Validate the flake"
          echo "  nix fmt            - Format Nix files"
          echo "  pre-commit install - Install git hooks"
          echo "  pre-commit run     - Run hooks on staged files"
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
