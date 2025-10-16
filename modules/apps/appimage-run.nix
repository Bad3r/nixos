{
  flake.nixosModules.apps."appimage-run" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."appimage-run" ];
    };
}
