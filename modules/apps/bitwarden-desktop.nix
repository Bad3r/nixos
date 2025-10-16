{
  flake.nixosModules.apps."bitwarden-desktop" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."bitwarden-desktop" ];
    };
}
