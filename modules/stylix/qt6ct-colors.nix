# Stylix's qt module sets `custom_palette = true` in the qt6ct/qt5ct configs
# but never generates the matching color scheme file -- the Base16 colors are
# baked only into Kvantum's kvconfig. Qt apps that don't load Kvantum (for
# example any QtQuick.Controls 2 app falling back to Fusion or Basic, like
# librepods) end up with default Qt colors instead of the Stylix palette.
#
# This module fills the gap by writing a qt6ct/qt5ct color scheme from the
# Stylix Base16 palette and pointing both qtct configs at it.
{ lib, ... }:
let
  # QPalette role order matches qt6ct's color scheme parser (21 entries,
  # mirroring `QPalette::ColorRole` 0..20; `Accent` is omitted -- qt6ct 0.11
  # does not yet include it).
  #
  # `BrightText` is Qt's high-contrast text role (used when `Text` would
  # render poorly on top of `Highlight`); it maps to `base07` (the brightest
  # foreground in Base16) rather than an accent colour.
  #
  # `HighlightedText` maps to `base05` rather than `base00`: on Base16
  # schemes where `base0D` (Highlight) and `base00` (background) collapse
  # toward similar luminance, selected text becomes unreadable. `base05`
  # keeps high contrast against any Highlight choice.
  paletteRoles = c: [
    c.base05 # WindowText
    c.base02 # Button
    c.base04 # Light
    c.base03 # Midlight
    c.base00 # Dark
    c.base01 # Mid
    c.base05 # Text
    c.base07 # BrightText
    c.base05 # ButtonText
    c.base00 # Base
    c.base00 # Window
    c.base00 # Shadow
    c.base0D # Highlight
    c.base05 # HighlightedText
    c.base0D # Link
    c.base0E # LinkVisited
    c.base01 # AlternateBase
    c.base00 # NoRole
    c.base00 # ToolTipBase
    c.base05 # ToolTipText
    c.base04 # PlaceholderText
  ];

  # Disabled-state palette mutes the foreground/highlight/link roles so
  # Fusion can render disabled controls with reduced contrast. qt6ct writes
  # the `disabled_colors` row verbatim and Qt no longer auto-greys widgets
  # under a custom palette, so identical active/disabled rows leave disabled
  # buttons (and rich-text labels with hyperlinks) looking fully active.
  # Background roles match the active palette to preserve widget silhouettes.
  disabledPaletteRoles = c: [
    c.base04 # WindowText
    c.base02 # Button
    c.base04 # Light
    c.base03 # Midlight
    c.base00 # Dark
    c.base01 # Mid
    c.base04 # Text
    c.base04 # BrightText
    c.base04 # ButtonText
    c.base00 # Base
    c.base00 # Window
    c.base00 # Shadow
    c.base02 # Highlight
    c.base04 # HighlightedText
    c.base04 # Link
    c.base04 # LinkVisited
    c.base01 # AlternateBase
    c.base00 # NoRole
    c.base00 # ToolTipBase
    c.base04 # ToolTipText
    c.base03 # PlaceholderText
  ];

  toArgb = colour: "#ff${lib.removePrefix "#" colour}";
  formatRow = colours: lib.concatStringsSep ", " (map toArgb colours);
  schemeText =
    {
      active,
      disabled,
    }:
    ''
      [ColorScheme]
      active_colors=${formatRow active}
      inactive_colors=${formatRow active}
      disabled_colors=${formatRow disabled}
    '';
in
{
  flake.homeManagerModules.base =
    { config, ... }:
    let
      stylixEnabled = (config.stylix.enable or false) && (config.stylix.targets.qt.enable or false);
      qtctActive = (config.qt.platformTheme.name or null) == "qtct";
      colours = config.lib.stylix.colors.withHashtag;
      relPath6 = "qt6ct/colors/stylix.conf";
      relPath5 = "qt5ct/colors/stylix.conf";
      absPath6 = "${config.xdg.configHome}/${relPath6}";
      absPath5 = "${config.xdg.configHome}/${relPath5}";
      schemeContents = schemeText {
        active = paletteRoles colours;
        disabled = disabledPaletteRoles colours;
      };
    in
    lib.mkIf (stylixEnabled && qtctActive) {
      xdg.configFile.${relPath6}.text = schemeContents;
      xdg.configFile.${relPath5}.text = schemeContents;

      qt.qt6ctSettings.Appearance.color_scheme_path = absPath6;
      qt.qt5ctSettings.Appearance.color_scheme_path = absPath5;
    };
}
