{
  flake.modules.nixos.apps.tor =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.tor ];
    };
}
