{
  flake.modules.nixos.apps.pkg-config =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.pkg-config ];
    };
}
