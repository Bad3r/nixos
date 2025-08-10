# Module: nixpkgs.nix
# Purpose: Configure nixpkgs path for legacy nix commands
# Namespace: flake.modules.nixos.base
# Priority: Default values that can be overridden

{
  flake.modules.nixos.base = { config, lib, ... }: {
    nix.nixPath = lib.mkDefault [
      "nixpkgs=${config.nixpkgs.flake.source}"
    ];
  };
}
