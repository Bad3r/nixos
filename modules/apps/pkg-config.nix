{
  flake.nixosModules.apps.pkg-config =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.pkg-config ];
    };
}
