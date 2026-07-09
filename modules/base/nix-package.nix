{ lib, ... }:
let
  polyModule =
    { pkgs, ... }:
    {
      # Lix (RFC #282). `latest` (>= 2.95) is required for the
      # `abort-on-warn` setting in modules/base/nix-settings.nix.
      # Rollback to CppNix: `nix.package = pkgs.nixVersions.latest`.
      nix.package = lib.mkDefault pkgs.lixPackageSets.latest.lix;
    };
in
{
  flake.nixosModules.base = polyModule;
  flake.homeManagerModules.base = polyModule;
}
