{
  flake.nixosModules.base =
    { config, lib, ... }:
    {
      nix = {
        channel.enable = false;
        nixPath = lib.mkDefault [
          "nixpkgs=${config.nixpkgs.flake.source}"
        ];

        # Resolve the `nixpkgs` registry alias (`nix run nixpkgs#pkg`,
        # `nix shell nixpkgs#pkg`, ...) to the personal fork instead of the
        # store-path pin that nixpkgs.flake.setFlakeRegistry installs by default.
        registry.nixpkgs.to = {
          type = "github";
          owner = "Bad3r";
          repo = "nixpkgs";
        };
      };

      # setNixPath is disabled alongside setFlakeRegistry: nixpkgs-flake asserts
      # `setNixPath -> setFlakeRegistry`, so leaving setNixPath at its default
      # (true) while setFlakeRegistry is false fails evaluation. The nix.nixPath
      # entry above keeps `<nixpkgs>` pinned to the system's own nixpkgs source.
      nixpkgs.flake = {
        setFlakeRegistry = false;
        setNixPath = false;
      };
    };
}
