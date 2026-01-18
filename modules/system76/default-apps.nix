/*
  System76 Default Applications

  Configures default applications for this host via XDG mimeapps.
  App modules install applications; this module designates which are default.

  Usage:
    system76.defaults.browser = "floorp";
    system76.defaults.terminal = "kitty";
    system76.defaults.fileManager = "nemo";
    system76.defaults.imageViewer = "nsxiv";
    system76.defaults.documentViewer = "zathura";
    system76.defaults.audioPlayer = "mpv";
    system76.defaults.videoPlayer = "mpv";

  To switch defaults, change these settings - no need to modify
  individual app modules.

  IMPORTANT: The corresponding app module must be enabled in apps-enable.nix.
  An assertion will fail if a default is set but the app module is disabled.
*/
{ config, lib, ... }:
let
  inherit (config.flake.lib) xdg;

  # Desktop file mappings from xdg.desktopFiles (single source of truth)
  inherit (xdg) desktopFiles;

  # Category metadata (MIME helpers, defaults, descriptions)
  # Desktop file mappings come from xdg.desktopFiles
  categoryMeta = {
    browser = {
      mkMimeDefaults = xdg.mime.mkBrowserDefaults;
      defaultValue = "floorp";
      example = "floorp";
      description = ''
        Default web browser for this host.
        Set to null to not configure a default browser via XDG mimeapps.
      '';
    };

    terminal = {
      mkMimeDefaults = xdg.mime.mkTerminalDefaults;
      defaultValue = "kitty";
      example = "kitty";
      description = ''
        Default terminal emulator for this host.
        Set to null to not configure a default terminal via XDG mimeapps.
      '';
      extraConfig = name: {
        environment.variables.TERMINAL = name;
        home-manager.sharedModules = [ { home.sessionVariables.TERMINAL = name; } ];
      };
    };

    fileManager = {
      mkMimeDefaults = xdg.mime.mkFileManagerDefaults;
      defaultValue = "nemo";
      example = "nemo";
      description = ''
        Default file manager for this host.
        Set to null to not configure a default file manager via XDG mimeapps.
      '';
    };

    imageViewer = {
      mkMimeDefaults = xdg.mime.mkImageViewerDefaults;
      defaultValue = "nsxiv";
      example = "nsxiv";
      description = ''
        Default image viewer for this host.
        Set to null to not configure a default image viewer via XDG mimeapps.
      '';
    };

    documentViewer = {
      mkMimeDefaults = xdg.mime.mkDocumentViewerDefaults;
      defaultValue = "zathura";
      example = "zathura";
      description = ''
        Default document viewer (PDF, EPUB, DjVu, etc.) for this host.
        Set to null to not configure a default document viewer via XDG mimeapps.
      '';
    };

    audioPlayer = {
      mkMimeDefaults = xdg.mime.mkAudioPlayerDefaults;
      defaultValue = "mpv";
      example = "mpv";
      description = ''
        Default audio player for this host.
        Set to null to not configure a default audio player via XDG mimeapps.
      '';
    };

    videoPlayer = {
      mkMimeDefaults = xdg.mime.mkVideoPlayerDefaults;
      defaultValue = "mpv";
      example = "mpv";
      description = ''
        Default video player for this host.
        Set to null to not configure a default video player via XDG mimeapps.
      '';
    };
  };

  # Merge desktop files with category metadata
  defaultAppCategories = lib.mapAttrs (
    name: meta: meta // { desktopFiles = desktopFiles.${name}; }
  ) categoryMeta;
in
{
  configurations.nixos.system76.module =
    { config, lib, ... }:
    let
      cfg = config.system76.defaults;

      # Generate a NixOS option for a category
      mkCategoryOption =
        _name: cat:
        lib.mkOption {
          type = lib.types.nullOr (lib.types.enum (lib.attrNames cat.desktopFiles));
          default = null;
          inherit (cat) example description;
        };

      # Generate config block for a category (system + user-level XDG mimeapps)
      mkCategoryConfig =
        name: cat:
        lib.mkIf (cfg.${name} != null) (
          lib.mkMerge [
            {
              xdg.mime.defaultApplications = cat.mkMimeDefaults cat.desktopFiles.${cfg.${name}}.desktop;
              home-manager.sharedModules = [
                {
                  xdg.mimeApps = {
                    enable = true;
                    defaultApplications = cat.mkMimeDefaults cat.desktopFiles.${cfg.${name}}.desktop;
                  };
                }
              ];
            }
            (if cat ? extraConfig then cat.extraConfig cfg.${name} else { })
          ]
        );

      # Generate assertion for a category: if default is set, app module must be enabled
      mkCategoryAssertion =
        name: cat:
        let
          value = cfg.${name};
          # value is constrained by enum type to valid keys in desktopFiles
          appInfo = cat.desktopFiles.${value};
          moduleName = appInfo.module;
          # Check module existence and enablement separately for proper error messages
          moduleExists = config.programs ? ${moduleName};
          hasExtended = moduleExists && config.programs.${moduleName} ? extended;
          hasEnable = hasExtended && config.programs.${moduleName}.extended ? enable;
          isEnabled = hasEnable && config.programs.${moduleName}.extended.enable;
        in
        lib.optional (value != null) {
          assertion = isEnabled;
          message =
            if !moduleExists then
              ''
                system76.defaults.${name} is set to "${value}" but the app module 'programs.${moduleName}' does not exist.
                Create the app module or set system76.defaults.${name} = null; to disable this default.
              ''
            else if !hasExtended then
              ''
                system76.defaults.${name} is set to "${value}" but 'programs.${moduleName}.extended' does not exist.
                The app module may not follow the expected pattern.
              ''
            else if !hasEnable then
              ''
                system76.defaults.${name} is set to "${value}" but 'programs.${moduleName}.extended.enable' does not exist.
                The app module may not follow the expected pattern.
              ''
            else
              ''
                system76.defaults.${name} is set to "${value}" but the app module is not enabled.
                Enable it with: programs.${moduleName}.extended.enable = true;
                Or set system76.defaults.${name} = null; to disable this default.
              '';
        };
    in
    {
      options.system76.defaults = lib.mapAttrs mkCategoryOption defaultAppCategories;

      config = lib.mkMerge (
        [
          # Assertions: verify app modules are enabled for configured defaults
          { assertions = lib.flatten (lib.mapAttrsToList mkCategoryAssertion defaultAppCategories); }
          # Set sensible defaults for all categories (can be overridden by explicit user settings)
          { system76.defaults = lib.mapAttrs (_: cat: lib.mkDefault cat.defaultValue) defaultAppCategories; }
        ]
        # Generate config blocks for each category
        ++ lib.mapAttrsToList mkCategoryConfig defaultAppCategories
      );
    };
}
