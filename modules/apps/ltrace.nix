{
  flake.nixosModules.apps.ltrace =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.ltrace ];
    };
}
