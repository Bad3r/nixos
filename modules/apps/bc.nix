{
  flake.nixosModules.apps.bc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.bc ];
    };
}
