/*
  Package: steam (with proton-ge extras)
  Description: Enables the Steam client on NixOS, including Proton-GE and helper tools for compatibility.
  Homepage: https://store.steampowered.com/
  Documentation: https://nixos.wiki/wiki/Steam
  Repository: https://github.com/ValveSoftware/steam-for-linux

  Summary:
    * Configures the Steam client with proton-ge-bin, dwarfs, fuse-overlayfs, and psmisc to improve Proton compatibility, game modding, and filesystem overlays.
    * Uses the NixOS `programs.steam` module to manage runtime dependencies, 32-bit libraries, and sandbox options.

  Options:
    programs.steam.enable = true; -- Turns on Steam support system-wide.
    programs.steam.extraCompatPackages: Additional Proton builds (e.g., Proton-GE) for better game support.
    programs.steam.extraPackages: Supplementary tools available within Steam runtime (overlayfs, dwarfs, etc.).

  Example Usage:
    * Enable this module and run `steam` to sign into the client and install games.
    * Switch compatibility tool per game to Proton-GE via Steam's Properties → Compatibility.
    * Use `steam-run <program>` for running binaries inside Steam runtime when troubleshooting.
*/

let
  steamModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.steam.extended;
    in
    {
      options.programs.steam.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Steam with Proton-GE and extended compatibility tools.";
        };

        package = lib.mkPackageOption pkgs "steam" { };

        extraTools = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = with pkgs; [
            dwarfs
            fuse-overlayfs
            psmisc
            protonup-rs
            freetype
            fontconfig
          ];
          description = ''
            Additional tools for game compatibility and modding support.

            - dwarfs: Compressed filesystem for game mods
            - fuse-overlayfs: Overlay filesystem for sandboxing
            - psmisc: Process utilities
            - protonup-rs: Manage Proton versions (including Experimental)
            - freetype: Font rendering library for Wine/Proton
            - fontconfig: Font configuration library
          '';
          example = lib.literalExpression "with pkgs; [ dwarfs fuse-overlayfs protonup-rs freetype ]";
        };
      };

      config = lib.mkIf cfg.enable {
        programs.steam = {
          enable = true;
          extraCompatPackages = [ pkgs.proton-ge-bin ];
          extraPackages = cfg.extraTools;
        };
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [
    "steam"
    "steam-unwrapped"
  ];
  flake.nixosModules.apps.steam = steamModule;
  flake.nixosModules.workstation = steamModule;
}
