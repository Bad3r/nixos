_:
let
  Overlay =
    { config, lib, ... }:
    let
      cfg = config.programs."electron-mail".extended;
      template = builtins.readFile ../../stylix/icons/electron-mail-outline.svg.mustache;
      render =
        template:
        config.lib.stylix.colors {
          inherit template;
          extension = ".svg";
        };
    in
    {
      config = lib.mkIf cfg.enable {
        nixpkgs.overlays = [
          (final: _prev: {
            "electron-mail" = final.callPackage ../../../packages/electron-mail {
              themedIcon = render template;
              # Tray glyph in the bar's status text color: each shade one slot darker.
              themedTrayIcon = render (
                builtins.replaceStrings
                  [ "{{base05-hex}}" "{{base04-hex}}" "{{base03-hex}}" ]
                  [ "{{base04-hex}}" "{{base03-hex}}" "{{base02-hex}}" ]
                  template
              );
            };
          })
        ];
      };
    };
in
{
  flake.customOverlays."electron-mail" = Overlay;
}
