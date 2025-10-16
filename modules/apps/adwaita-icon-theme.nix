{
  flake.nixosModules.apps."adwaita-icon-theme" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."adwaita-icon-theme" ];
    };
}
