{
  flake.nixosModules.apps."open-in-mpv" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."open-in-mpv" ];
    };
}
