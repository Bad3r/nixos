/*
  Package: steam
  Description: Steam game client and digital distribution platform.
  Homepage: https://store.steampowered.com/
  Documentation: https://nixos.wiki/wiki/Steam
  Repository: nil

  Notes:
    * Includes Proton-GE.
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
          inherit (cfg) package;
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
}
