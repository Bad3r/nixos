_:
let
  body =
    { pkgs, ... }:
    {
      services.xserver = {
        enable = true;
        excludePackages = [ pkgs.xterm ];
        xkb = {
          layout = "us";
          variant = "";
        };
      };
    };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
