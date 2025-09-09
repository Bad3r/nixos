{
  flake.nixosModules.base =
    { config, lib, ... }:
    {
      nix.nixPath = lib.mkDefault [
        "nixpkgs=${config.nixpkgs.flake.source}"
      ];
    };
}
