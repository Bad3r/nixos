/*
  Package: telegram-desktop
  Description: Telegram Desktop messaging app.
  Homepage: https://desktop.telegram.org/
  Documentation: https://telegram.org/faq

  Notes:
    * Telegram has no theme option, config file, or startup flag: it keeps the applied theme in
      its own tdata, so the module only ships the theme file. Apply it once from Settings > Chat
      Settings > Chat wallpaper > Choose from file, pick
      ~/.local/share/tdesktop-themes/vscode-dark-2026.tdesktop-theme, then Keep changes.
    * _theme.py derives every key in Telegram's colors.palette from the Stylix palette, with
      Telegram's night theme filling keys it does not map, both read from the package's source.
    * Telegram watches the applied file and reloads it when its old target is deleted, so a
      palette change lands after the next garbage collection or on a manual reapply.
*/

_: {
  flake.homeManagerModules.apps.telegram-desktop =
    {
      config,
      osConfig,
      lib,
      pkgs,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [
        "programs"
        "telegram-desktop"
        "extended"
        "enable"
      ] false osConfig;
      inherit (osConfig.programs.telegram-desktop.extended.package.unwrapped) src;
      colors = config.lib.stylix.colors.withHashtag;

      vscode = import ../../stylix/_vscode-dark-2026.nix;
      palette = {
        accent = vscode."statusBarItem.prominentBackground";
        link = vscode."textLink.foreground";
        selection = vscode."quickInputList.focusBackground";
        editorSelection = vscode."editor.selectionBackground";
        popup = vscode."quickInput.background";
        hover = vscode."activityBar.activeBackground";
        badge = vscode."badge.background";
      };

      baseNames = map (digit: "base0${digit}") (lib.stringToCharacters "0123456789ABCDEF");

      theme =
        pkgs.runCommand "vscode-dark-2026.tdesktop-theme"
          {
            nativeBuildInputs = [ pkgs.python3 ];
            colors = builtins.toJSON (lib.genAttrs baseNames (name: colors.${name}) // palette);
            passAsFile = [ "colors" ];
          }
          ''
            python3 -I ${./_theme.py} \
              ${src}/Telegram/lib_ui/ui/colors.palette \
              ${src}/Telegram/Resources/night.tdesktop-theme \
              "$colorsPath" "$out"
          '';
    in
    {
      config = lib.mkIf nixosEnabled {
        xdg.dataFile."tdesktop-themes/vscode-dark-2026.tdesktop-theme".source = theme;
      };
    };
}
