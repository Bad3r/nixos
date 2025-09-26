{
  flake.nixosModules.apps.git =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.git ];
    };
}
