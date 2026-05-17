{
  flake.nixosModules.base =
    { config, lib, ... }:
    {
      nix.channel.enable = false;
      nix.nixPath = lib.mkDefault [
        "nixpkgs=${config.nixpkgs.flake.source}"
      ];
    };
}
