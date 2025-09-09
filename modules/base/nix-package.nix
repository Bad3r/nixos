{ lib, ... }:
let
  polyModule =
    { pkgs, ... }:
    {
      nix.package =
        let
          versions = lib.attrNames pkgs.nixVersions;
          nixVersions = lib.filter (lib.hasPrefix "nix_") versions;
          sorted = lib.naturalSort nixVersions;
          latest = lib.last sorted;
          package = lib.getAttr latest pkgs.nixVersions;
        in
        lib.mkDefault package;
    };
in
{
  flake.nixosModules.base = polyModule;
  flake.homeManagerModules.base = polyModule;
}
