{
  flake.nixosModules.apps.mpv =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        mpv
        mpvScripts.thumbfast
        mpv-shim-default-shaders
        mpvScripts.mpv-cheatsheet
        open-in-mpv
        jellyfin-mpv-shim
      ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        mpv
        mpvScripts.thumbfast
        mpv-shim-default-shaders
        mpvScripts.mpv-cheatsheet
        open-in-mpv
        jellyfin-mpv-shim
      ];
    };
}
