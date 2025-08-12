# Priority: Default values that can be overridden

{
  flake.modules.nixos.base = { config, lib, ... }: {
    nix.nixPath = lib.mkDefault [
      "nixpkgs=${config.nixpkgs.flake.source}"
    ];
  };
}
