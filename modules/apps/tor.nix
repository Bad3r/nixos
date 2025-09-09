{
  flake.nixosModules.apps.tor =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.tor ];
    };
}
