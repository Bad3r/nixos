{
  flake.nixosModules.apps.which =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.which ];
    };
}
