{
  config,
  lib,
  ...
}:
let
  parts = config.flake.lib.fonts.officeParts;
  complete = builtins.all builtins.pathExists parts;
  fontPackages = config.flake.lib.fonts.packages;
in
{
  nixpkgs.allowedUnfreePackages = [
    "vista-fonts"
    "windows-office-fonts"
  ];
  flake.nixosModules.hosts-common.imports = [
    ({ pkgs, ... }: {
      assertions = [
        {
          assertion = !(builtins.any builtins.pathExists parts) || complete;
          message = "Windows/Office font archive is incomplete; initialize the secrets submodule at its pinned commit.";
        }
      ];
      fonts.packages = [
        pkgs.vista-fonts
      ]
      ++ lib.optional complete (fontPackages pkgs).windows-office-fonts;
    })
  ];
}
