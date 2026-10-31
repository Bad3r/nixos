/*
  Package: snixembed
  Description: SNI-to-XEmbed tray bridge that lets KDE/Plasma StatusNotifierItem
    icons render inside legacy XEmbed system trays (i3bar, polybar, xfce4-panel).
  Homepage: https://git.sr.ht/~steef/snixembed
  Documentation: https://git.sr.ht/~steef/snixembed/tree/main/README.md
  Repository: https://git.sr.ht/~steef/snixembed
*/
_:
let
  SnixembedModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.snixembed.extended;
    in
    {
      options.programs.snixembed.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable snixembed.";
        };

        package = lib.mkPackageOption pkgs "snixembed" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.snixembed = SnixembedModule;
}
