{
  flake.nixosModules.apps."mpv-thumbfast" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.mpvScripts.thumbfast ];
    };
}
