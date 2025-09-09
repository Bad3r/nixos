{
  flake.modules.nixos.apps.go =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.go ];
    };
}
