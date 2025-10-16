{
  flake.nixosModules.apps."mpv-with-scripts" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.mpv ];
    };
}
