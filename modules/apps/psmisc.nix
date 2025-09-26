{
  flake.nixosModules.apps.psmisc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.psmisc ];
    };
}
