{
  flake.nixosModules.apps.lshw =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.lshw ];
    };
}
