{ inputs, ... }:
{
  imports = [
    inputs.treefmt-nix.flakeModule
    inputs.make-shell.flakeModules.default
  ];
  perSystem =
    { pkgs, config, ... }:
    {
      # Use make-shells pattern for better modularity
      make-shells.default = {
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
          echo "  write-files        - Generate managed files (README.md)"
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
