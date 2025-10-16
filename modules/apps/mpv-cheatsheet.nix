{
  flake.nixosModules.apps."mpv-cheatsheet" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.mpvScripts."mpv-cheatsheet" ];
    };
}
