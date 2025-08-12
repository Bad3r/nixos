
# Development shell for NixOS configuration
{ inputs, ... }:
{
  # Configure treefmt
  imports = [ inputs.treefmt-nix.flakeModule ];
  
  perSystem = { pkgs, config, ... }: {
    devShells.default = pkgs.mkShell {
      packages = with pkgs; [
        # Nix tools
        nixpkgs-fmt
        statix
        deadnix
        nil # Nix LSP
        nix-tree
        nix-diff
        
        # Useful for checking configuration
        jq
        yq
        
        # Git hooks from inputs
        config.treefmt.build.wrapper
      ];
      
      shellHook = ''
        echo "🚀 NixOS Configuration Development Shell"
        echo ""
        echo "Available commands:"
        echo "  nix flake check    - Validate the flake"
        echo "  nix flake show     - Show flake outputs"
        echo "  nix fmt            - Format Nix files"
        echo "  nix build .#nixosConfigurations.system76.config.system.build.toplevel"
        echo "                     - Build the system configuration"
        echo "  nixos-rebuild build --flake .#system76"
        echo "                     - Build using nixos-rebuild"
        echo ""
        echo "Useful tools:"
        echo "  statix check       - Static analysis"
        echo "  deadnix            - Find dead code"
        echo "  nix-tree           - Explore dependencies"
        echo ""
      '';
    };
    
    # Configure treefmt
    treefmt = {
      projectRootFile = "flake.nix";
      programs = {
        nixpkgs-fmt.enable = true;
        prettier.enable = true;
        shfmt.enable = true;
      };
      
      settings.formatter.prettier = {
        excludes = [ "*.md" ];
      };
    };
  };
}