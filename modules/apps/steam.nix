/*
  Package: steam (with proton-ge extras)
  Description: Enables the Steam client on NixOS, including Proton-GE and helper tools for compatibility.
  Homepage: https://store.steampowered.com/
  Documentation: https://nixos.wiki/wiki/Steam
  Repository: https://github.com/ValveSoftware/steam-for-linux

  Summary:
    * Configures the Steam client with proton-ge-bin, dwarfs, fuse-overlayfs, and psmisc to improve Proton compatibility, game modding, and filesystem overlays.
    * Leverages the NixOS `programs.steam` module to manage runtime dependencies, 32-bit libraries, and sandbox options.

  Options:
    programs.steam.enable = true; — Turns on Steam support system-wide.
    programs.steam.extraCompatPackages: Additional Proton builds (e.g., Proton-GE) for better game support.
    programs.steam.extraPackages: Supplementary tools available within Steam runtime (overlayfs, dwarfs, etc.).

  Example Usage:
    * Enable this module and run `steam` to sign into the client and install games.
    * Switch compatibility tool per game to Proton-GE via Steam’s Properties → Compatibility.
    * Use `steam-run <program>` for running binaries inside Steam runtime when troubleshooting.
*/

{
  nixpkgs.allowedUnfreePackages = [
    "steam"
    "steam-unwrapped"
  ];

  flake.nixosModules =
    let
      steamModule =
        { pkgs, ... }:
        {
          programs.steam = {
            enable = true;
            extraCompatPackages = [ pkgs.proton-ge-bin ];
            extraPackages = with pkgs; [
              dwarfs
              fuse-overlayfs
              psmisc
            ];
          };
        };
    in
    {
      apps.steam = steamModule;
      pc = steamModule;
    };
}
