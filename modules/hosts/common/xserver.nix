_:
let
  body = {
    services.xserver = {
      enable = true;
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
