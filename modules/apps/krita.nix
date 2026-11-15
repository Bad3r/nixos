/*
  Package: krita
  Description: Free and open source painting application.
  Homepage: https://krita.org/
  Documentation: https://docs.krita.org/
  Repository: https://invent.kde.org/graphics/krita

  Summary:
    * Digital painting and illustration with brushes, layers, and advanced color management.

  Notes:
    * Krita keeps only the Fusion or Breeze widget style, so Kvantum never applies; it
      colors Fusion from the KDE color scheme set in /etc/xdg/kritarc, and a theme picked
      under Settings > Themes overrides it in ~/.config/kritarc.
*/
_:
let
  KritaModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.krita.extended;
      package = pkgs.symlinkJoin {
        inherit (cfg.package) name version meta;
        paths = [ cfg.package ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram "$out/bin/krita" --add-flags --nosplash
        '';
      };
    in
    {
      options.programs.krita.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable krita.";
        };

        package = lib.mkPackageOption pkgs "krita" { };
      };

      config = lib.mkIf cfg.enable {
        environment = {
          systemPackages = [ package ];
          # Theme names the [General] Name of a share/color-schemes file.
          etc."xdg/kritarc".text = lib.generators.toINI { } {
            theme.Theme = config.lib.stylix.colors.scheme;
          };
        };
      };
    };
in
{
  flake.nixosModules.apps.krita = KritaModule;
}
