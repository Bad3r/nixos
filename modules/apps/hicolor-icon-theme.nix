{
  flake.nixosModules.apps."hicolor-icon-theme" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."hicolor-icon-theme" ];
    };
}
