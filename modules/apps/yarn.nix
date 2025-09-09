{
  flake.modules.nixos.apps.yarn =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.yarn ];
    };
}
