{ lib, ... }:
let
  polyModule =
    { pkgs, ... }:
    {
      # Lix (RFC #282). `latest` (>= 2.95) is required for the
      # `abort-on-warn` setting in modules/base/nix-settings.nix.
      # Rollback to CppNix: revert this commit. Swapping nix.package alone is
      # insufficient — modules/base/nix-settings.nix carries the Lix-only
      # feature names pipe-operator/flake-self-attrs, which the CppNix nix.conf
      # check rejects.
      nix.package = lib.mkDefault pkgs.lixPackageSets.latest.lix;
    };
in
{
  flake.nixosModules.base = polyModule;
  flake.homeManagerModules.base = polyModule;
}
