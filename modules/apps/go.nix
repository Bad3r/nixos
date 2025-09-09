{
  flake.nixosModules.apps.go =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.go ];
    };
}
