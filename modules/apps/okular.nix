{
  flake.modules.nixos.apps.okular =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.kdePackages.okular ];
    };
}
