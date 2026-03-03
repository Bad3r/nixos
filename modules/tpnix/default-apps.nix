/*
  Tpnix Default Applications

  Configures default applications for this host via XDG mimeapps.
  App modules install applications; this module designates which are default.

  Usage:
    tpnix.defaults.browser = "floorp";
    tpnix.defaults.terminal = "kitty";
    tpnix.defaults.fileManager = "nemo";
    tpnix.defaults.archiveManager = "file-roller";
    tpnix.defaults.imageViewer = "nsxiv";
    tpnix.defaults.documentViewer = "zathura";
    tpnix.defaults.audioPlayer = null;
    tpnix.defaults.videoPlayer = null;
    tpnix.defaults.editor = "nvim";
    tpnix.defaults.pager = "less";
    tpnix.defaults.diffProgram = "nvim -d";
    tpnix.defaults.opener = "xdg-open";

  To switch defaults, change these settings - no need to modify
  individual app modules.

  IMPORTANT: The corresponding app module must be enabled in apps-enable.nix.
  An assertion will fail if a default is set but the app module is disabled.
  (This does not apply to env-only categories like pager and diffProgram.)
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
      extraConfig = name: {
        environment.variables.BROWSER = name;
        home-manager.sharedModules = [ { home.sessionVariables.BROWSER = name; } ];
      };
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
        environment.variables = {
          TERMINAL = name;
          COLORTERM = "truecolor";
        };
        home-manager.sharedModules = [
          {
            home.sessionVariables = {
              TERMINAL = name;
              COLORTERM = "truecolor";
            };
          }
        ];
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
      extraConfig = name: {
        environment.variables.FILE_MANAGER = name;
        home-manager.sharedModules = [ { home.sessionVariables.FILE_MANAGER = name; } ];
      };
    };

    archiveManager = {
      mkMimeDefaults = xdg.mime.mkArchiveManagerDefaults;
      defaultValue = "file-roller";
      example = "file-roller";
      description = ''
        Default archive manager (zip, tar, 7z, rar, etc.) for this host.
        Set to null to not configure a default archive manager via XDG mimeapps.
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
      extraConfig = name: {
        environment.variables.IMAGE = name;
        home-manager.sharedModules = [ { home.sessionVariables.IMAGE = name; } ];
      };
    };

    documentViewer = {
      mkMimeDefaults = xdg.mime.mkDocumentViewerDefaults;
      defaultValue = "zathura";
      example = "zathura";
      description = ''
        Default document viewer (PDF, EPUB, DjVu, etc.) for this host.
        Set to null to not configure a default document viewer via XDG mimeapps.
      '';
      extraConfig = name: {
        environment.variables.READER = name;
        home-manager.sharedModules = [ { home.sessionVariables.READER = name; } ];
      };
    };

    audioPlayer = {
      mkMimeDefaults = xdg.mime.mkAudioPlayerDefaults;
      defaultValue = null;
      example = "mpv";
      description = ''
        Default audio player for this host.
        Set to null to not configure a default audio player via XDG mimeapps.
      '';
    };

    videoPlayer = {
      mkMimeDefaults = xdg.mime.mkVideoPlayerDefaults;
      defaultValue = null;
      example = "mpv";
      description = ''
        Default video player for this host.
        Set to null to not configure a default video player via XDG mimeapps.
      '';
      extraConfig = name: {
        environment.variables.VIDEO_PLAYER = name;
        home-manager.sharedModules = [ { home.sessionVariables.VIDEO_PLAYER = name; } ];
      };
    };
  };

  # Environment-only categories (no MIME types, just env vars)
  envOnlyMeta = {
    editor = {
      defaultValue = "nvim";
      example = "nvim";
      description = ''
        Default text editor for this host.
        Sets EDITOR and VISUAL environment variables.
      '';
      extraConfig = value: {
        environment.variables = {
          EDITOR = value;
          VISUAL = value;
        };
        home-manager.sharedModules = [
          {
            home.sessionVariables = {
              EDITOR = value;
              VISUAL = value;
            };
          }
        ];
      };
    };

    pager = {
      defaultValue = "less";
      example = "bat";
      description = ''
        Default pager for this host.
        Sets PAGER, MANPAGER, and MANWIDTH environment variables.
      '';
      extraConfig = value: {
        environment.variables = {
          PAGER = value;
          MANPAGER = value;
          MANWIDTH = "120";
        };
        home-manager.sharedModules = [
          {
            home.sessionVariables = {
              PAGER = value;
              MANPAGER = value;
              MANWIDTH = "120";
            };
          }
        ];
      };
    };

    diffProgram = {
      defaultValue = "nvim -d";
      example = "nvim -d";
      description = ''
        Default diff program for this host.
        Sets DIFFPROG environment variable (used by pacdiff, etc.).
      '';
      extraConfig = value: {
        environment.variables.DIFFPROG = value;
        home-manager.sharedModules = [ { home.sessionVariables.DIFFPROG = value; } ];
      };
    };

    opener = {
      defaultValue = "xdg-open";
      example = "xdg-open";
      description = ''
        Default generic file opener for this host.
        Sets OPENER environment variable (delegates to XDG MIME handlers).
      '';
      extraConfig = value: {
        environment.variables.OPENER = value;
        home-manager.sharedModules = [ { home.sessionVariables.OPENER = value; } ];
      };
    };
  };

  # Merge desktop files with category metadata
  defaultAppCategories = lib.mapAttrs (
    name: meta: meta // { desktopFiles = desktopFiles.${name}; }
  ) categoryMeta;
in
{
  configurations.nixos.tpnix.module =
    {
      config,
      lib,
      options,
      ...
    }:
    let
      cfg = config.tpnix.defaults;
      hasHomeManager = options ? home-manager;

      # Generate a NixOS option for a MIME category
      mkCategoryOption =
        _name: cat:
        lib.mkOption {
          type = lib.types.nullOr (lib.types.enum (lib.attrNames cat.desktopFiles));
          default = null;
          inherit (cat) example description;
        };

      # Generate a NixOS option for an env-only category
      mkEnvOnlyOption =
        _name: cat:
        lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          inherit (cat) example description;
        };

      # Generate config block for a MIME category (system + user-level XDG mimeapps)
      mkCategoryConfig =
        name: cat:
        lib.mkIf (cfg.${name} != null) (
          lib.mkMerge [
            { xdg.mime.defaultApplications = cat.mkMimeDefaults cat.desktopFiles.${cfg.${name}}.desktop; }
            # Set user-level XDG mimeapps if home-manager is available
            (lib.optionalAttrs hasHomeManager {
              home-manager.sharedModules = [
                {
                  xdg.mimeApps = {
                    enable = true;
                    defaultApplications = cat.mkMimeDefaults cat.desktopFiles.${cfg.${name}}.desktop;
                  };
                }
              ];
            })
            (lib.optionalAttrs (cat ? extraConfig) (cat.extraConfig cfg.${name}))
          ]
        );

      # Generate config block for an env-only category (just environment variables)
      mkEnvOnlyConfig = name: cat: lib.mkIf (cfg.${name} != null) (cat.extraConfig cfg.${name});

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
                tpnix.defaults.${name} is set to "${value}" but the app module 'programs.${moduleName}' does not exist.
                Create the app module or set tpnix.defaults.${name} = null; to disable this default.
              ''
            else if !hasExtended then
              ''
                tpnix.defaults.${name} is set to "${value}" but 'programs.${moduleName}.extended' does not exist.
                The app module may not follow the expected pattern.
              ''
            else if !hasEnable then
              ''
                tpnix.defaults.${name} is set to "${value}" but 'programs.${moduleName}.extended.enable' does not exist.
                The app module may not follow the expected pattern.
              ''
            else
              ''
                tpnix.defaults.${name} is set to "${value}" but the app module is not enabled.
                Enable it with: programs.${moduleName}.extended.enable = true;
                Or set tpnix.defaults.${name} = null; to disable this default.
              '';
        };
    in
    {
      options.tpnix.defaults =
        (lib.mapAttrs mkCategoryOption defaultAppCategories) // (lib.mapAttrs mkEnvOnlyOption envOnlyMeta);

      config = lib.mkMerge (
        [
          # Assertions: verify app modules are enabled for configured defaults (MIME categories only)
          { assertions = lib.flatten (lib.mapAttrsToList mkCategoryAssertion defaultAppCategories); }
          # Set sensible defaults for all categories (can be overridden by explicit user settings)
          { tpnix.defaults = lib.mapAttrs (_: cat: lib.mkDefault cat.defaultValue) defaultAppCategories; }
          { tpnix.defaults = lib.mapAttrs (_: cat: lib.mkDefault cat.defaultValue) envOnlyMeta; }
        ]
        # Generate config blocks for MIME categories
        ++ lib.mapAttrsToList mkCategoryConfig defaultAppCategories
        # Generate config blocks for env-only categories
        ++ lib.mapAttrsToList mkEnvOnlyConfig envOnlyMeta
      );
    };
}
