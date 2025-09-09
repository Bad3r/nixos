{
  flake.modules.nixos.apps.python =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.python312 ];
    };
}
