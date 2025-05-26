{
  description = "Modular multi-host NixOS & macOS configuration";

  # This is the standard format for flake.nix.
  # `inputs` are the dependencies of the flake,
  # and `outputs` function will return all the build results of the flake.
  # Each item in `inputs` will be passed as a parameter to
  # the `outputs` function after being pulled and built.

  inputs = {
    # There are many ways to reference flake inputs.
    # The most widely used is `github:owner/name/reference`,
    # which represents the GitHub repository URL + branch/commit-id/tag.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    impermanence.url = "github:nix-community/impermanence";
    # Also see the 'stable-packages' and 'master-packages' overlays at 'overlays/default.nix'.
    treefmt-nix.url = "github:numtide/treefmt-nix";

    home-manager = {
      url = "github:nix-community/home-manager";
      # The `follows` keyword in inputs is used for inheritance.
      # Here, `inputs.nixpkgs` of home-manager is kept consistent with
      # the `inputs.nixpkgs` of the current flake,
      # to avoid problems caused by different versions of nixpkgs.
      inputs.nixpkgs.follows = "nixpkgs";
    };

    plasma-manager = {
      url = "github:pjones/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # https://www.nyx.chaotic.cx/#lists-of-options-and-packages
    # chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
  };

  outputs =
    { self, nixpkgs, home-manager, nixos-hardware, treefmt-nix, ... }@inputs:
    let
      lib = nixpkgs.lib;
      supportedSystems = {
        linux = "x86_64-linux";
        darwin = "x86_64-darwin";
      };

      # List of system types to support
      systems = [ "x86_64-linux" "x86_64-darwin" ];

      # host discovery
      discoverHosts = type:
        let
          dir = ./hosts/${type};
          entries = builtins.attrNames (builtins.readDir dir);
          validHost = host:
            builtins.pathExists (dir + "/${host}/default.nix")
            && (!lib.hasPrefix "." host);
        in lib.filter validHost entries;

      linuxHosts = discoverHosts "linux";
      darwinHosts = discoverHosts "darwin";
      commonMods = [ ./modules/common ];

      # Small tool to iterate over each systems
      eachSystem = f:
        nixpkgs.lib.genAttrs systems (system:
          f (import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          }));
      # Eval the treefmt modules from ./treefmt.nix
      treefmtEval = eachSystem
        (pkgs: treefmt-nix.lib.evalModule pkgs ./modules/common/treefmt.nix);
    in {
      nixosConfigurations = lib.genAttrs linuxHosts (host:
        lib.nixosSystem {
          specialArgs = {
            inherit inputs lib;
          }; # Pass inputs and lib to all modules
          pkgs = import nixpkgs {
            hostPlatform = {
              gcc.arch = "x86-64-v3";
              gcc.tune = "x86-64-v3";
              system = supportedSystems.linux;
            };
            config.allowUnfree = true;
            overlays = [
              (import ./overlays/input-packages.nix
                inputs) # pkgs.master & pkgs.stable overlays
            ];
          };
          modules = commonMods ++ [
            ./modules/linux
            ./hosts/linux/${host}
            home-manager.nixosModules.home-manager
            {
              # Nix configuration module
              nix.settings = {
                experimental-features = [ "nix-command" "flakes" ];
                substituters = [
                  "https://cache.nixos.org"
                  "https://nix-community.cachix.org"
                ];
                trusted-public-keys = [
                  "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
                  "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
                ];
              };

              # Add home-manager command to system packages
              environment.systemPackages = [
                home-manager.packages.${supportedSystems.linux}.home-manager
              ];

              # Home-manager configuration
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                sharedModules = [ ./modules/common/home.nix ];
                extraSpecialArgs = { inherit inputs; };
                backupFileExtension = "backup";
              };
            }
          ];
        });

      # for `nix fmt`
      formatter =
        eachSystem (pkgs: treefmtEval.${pkgs.system}.config.build.wrapper);
      # for `nix flake check`
      checks = eachSystem (pkgs: {
        formatting = treefmtEval.${pkgs.system}.config.build.check self;
      });
    };
}
