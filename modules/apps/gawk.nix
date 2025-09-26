{
  flake.nixosModules.apps.gawk =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gawk ];
    };
}
