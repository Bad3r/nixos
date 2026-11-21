/*
  KDE color scheme generated from VS Code Dark 2026.

  KColorScheme reads kdeglobals, not the Qt palette that qt6ct and Kvantum
  provide. Outside Plasma, a KDE Frameworks app with no scheme configured
  applies the compiled-in Breeze Dark palette over qt6ct, and plain
  KColorScheme lookups fall back to Breeze light. Krita builds its whole
  palette from a named scheme the same way.

  The scheme ships in share/color-schemes and becomes the system default
  through /etc/xdg/kdeglobals, which KConfig cascades under each user's own
  kdeglobals, so a scheme picked in an app still wins.
*/
{ lib, ... }:
let
  vscode = import ./_vscode-dark-2026.nix;

  KdeColorSchemeModule =
    { config, pkgs, ... }:
    let
      colors = config.lib.stylix.colors.withHashtag;
      name = config.lib.stylix.colors.scheme;
      id = lib.concatStrings (lib.filter lib.isString (builtins.split "[^a-zA-Z0-9]" name));

      triple =
        hex:
        lib.concatMapStringsSep "," (i: toString (lib.fromHexString (builtins.substring i 2 hex))) [
          1
          3
          5
        ];

      accent = vscode."menu.selectionBorder";
      roles = {
        ForegroundNormal = vscode."foreground";
        ForegroundInactive = colors.base04; # descriptionForeground
        ForegroundActive = vscode."list.highlightForeground";
        ForegroundLink = vscode."textLink.foreground";
        ForegroundVisited = vscode."charts.purple";
        ForegroundNegative = vscode."errorForeground";
        ForegroundNeutral = vscode."list.warningForeground";
        ForegroundPositive = vscode."gitDecoration.addedResourceForeground";
        DecorationFocus = accent;
        DecorationHover = accent;
      };
      colorSet = overrides: lib.mapAttrs (_: triple) (roles // overrides);

      window = colorSet {
        BackgroundNormal = colors.base01; # sideBar.background
        BackgroundAlternate = vscode."editor.lineHighlightBackground";
      };

      scheme = {
        General = {
          ColorScheme = id;
          Name = name;
        };

        # Disabled text fades toward the background, landing near disabledForeground.
        "ColorEffects:Disabled" = {
          ColorEffect = 0;
          ContrastEffect = 1;
          ContrastAmount = 0.65;
          IntensityEffect = 0;
        };
        # Unfocused windows keep their colors; the selection dims to a blue-tinted window color.
        "ColorEffects:Inactive" = {
          Enable = false;
          ChangeSelectionColor = true;
        };

        "Colors:Window" = window;
        "Colors:Header" = window;
        "Colors:Complementary" = window;
        "Colors:View" = colorSet {
          BackgroundNormal = colors.base00; # editor.background
          BackgroundAlternate = colors.base01;
          ForegroundNormal = colors.base05; # editor.foreground
        };
        "Colors:Button" = colorSet {
          BackgroundNormal = colors.base02; # widget.border, as the Kvantum button
          BackgroundAlternate = vscode."editor.selectionBackground";
        };
        "Colors:Selection" = colorSet {
          BackgroundNormal = vscode."quickInputList.focusBackground";
          BackgroundAlternate = vscode."editor.selectionBackground";
          ForegroundNormal = vscode."quickInputList.focusForeground";
          ForegroundActive = vscode."quickInputList.focusForeground";
          ForegroundInactive = vscode."list.activeSelectionForeground";
          ForegroundLink = vscode."quickInputList.focusForeground";
        };
        "Colors:Tooltip" = colorSet {
          BackgroundNormal = vscode."editorWidget.background";
          BackgroundAlternate = colors.base01;
          ForegroundNormal = colors.base05;
        };
      };

      toIni = lib.generators.toINI { };
    in
    {
      config = lib.mkIf config.services.graphical-desktop.enable {
        environment = {
          systemPackages = [ (pkgs.writeTextDir "share/color-schemes/${id}.colors" (toIni scheme)) ];
          pathsToLink = [ "/share/color-schemes" ];
          # UiSettings selects the scheme for KColorSchemeManager.
          etc."xdg/kdeglobals".text = toIni (scheme // { UiSettings.ColorScheme = id; });
        };
      };
    };
in
{
  flake.nixosModules.base = KdeColorSchemeModule;
}
