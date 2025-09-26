{
  flake.nixosModules.apps.sysstat =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.sysstat ];
    };
}
