/*
  Package: flameshot
  Description: Powerful yet simple to use screenshot software.
  Homepage: https://github.com/flameshot-org/flameshot
  Documentation: https://flameshot.org/docs/
  Repository: https://github.com/flameshot-org/flameshot

  Summary:
    * Captures screenshots with configurable annotations, blur, arrows, highlighting, and upload/share integrations.
    * Supports system tray controls, DBus shortcuts, Wayland/X11 backends, and custom keyboard shortcuts.

  Options:
    --raw: Pipe capture data to stdout for scripting (usable with `flameshot gui --raw`).
    --delay <ms>: Add a delay before capture begins, allowing time to stage windows.
    --number <index>: Capture a specific monitor in multi-display setups (`flameshot screen --number`).
    --path <dir>: Save screenshots to a particular directory instead of prompting (`flameshot full --path`).

  Example Usage:
    * `flameshot gui` — Draw annotations, blur sensitive data, and copy to clipboard before sharing.
    * `flameshot full --path ~/Pictures/screenshots` — Save a full display capture directly to a folder.
    * `flameshot gui --delay 3000` — Start a capture after a 3-second delay to stage windows.
*/

_: {
  flake.homeManagerModules.apps.flameshot =
    {
      osConfig,
      config,
      lib,
      pkgs,
      metaOwner,
      ...
    }:
    let
      enabled = lib.attrByPath [ "services" "flameshot" "extended" "enable" ] false osConfig;
      stylixColors = lib.attrByPath [ "lib" "stylix" "colors" ] { } config;
      stylixColorsWithHash = lib.attrByPath [ "withHashtag" ] { } stylixColors;
      getColor =
        name:
        if lib.hasAttr name stylixColorsWithHash then
          stylixColorsWithHash.${name}
        else if lib.hasAttr name stylixColors then
          stylixColors.${name}
        else
          "#740096";
      # Use metaOwner instead of config.home.homeDirectory
      homeDirectory = "/home/${metaOwner.username}";
      mkPicturesDir =
        let
          picturesDirRaw = config.xdg.userDirs.pictures or null;
        in
        if picturesDirRaw == null then "${homeDirectory}/Pictures" else picturesDirRaw;
      mkScreenshotDir = "${mkPicturesDir}/screenshots";
    in
    {
      config = lib.mkIf enabled {
        xdg.userDirs.enable = lib.mkDefault true;
        xdg.userDirs.createDirectories = lib.mkDefault true;

        home.activation.ensureFlameshotScreenshotDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          mkdir -p '${mkScreenshotDir}'
        '';

        services.flameshot = {
          enable = true;
          package = pkgs.flameshot;
          settings = {
            General = {
              copyOnDoubleClick = true;
              saveLastRegion = true;
              copyPathAfterSave = true;
              savePath = mkScreenshotDir;
              savePathFixed = true;
              uiColor = getColor "base0D";
              contrastUiColor = getColor "base01";
            };
          };
        };
      };
    };
}
