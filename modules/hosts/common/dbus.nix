{ lib, ... }:
let
  body =
    { pkgs, ... }:
    {
      services.dbus = {
        enable = true;
        packages = lib.mkAfter [ pkgs.dconf ];
      };
    };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
