{
  flake.modules.nixos.apps.ltrace =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.ltrace ];
    };
}
