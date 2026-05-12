/*
  Default Applications (common baseline)

  Configures default applications via XDG mimeapps. App modules install
  applications; this module designates which are the host's defaults.

  Usage:
    host.defaults.browser = "floorp";
    host.defaults.mailClient = "thunderbird";
    host.defaults.torrentClient = "qbittorrent";
    host.defaults.terminal = "kitty";
    host.defaults.fileManager = "nemo";
    host.defaults.archiveManager = "file-roller";
    host.defaults.imageViewer = "nsxiv";
    host.defaults.documentViewer = "zathura";
    host.defaults.audioPlayer = "mpv";
    host.defaults.videoPlayer = "mpv";
    host.defaults.editor = "nvim";
    host.defaults.pager = "less";
    host.defaults.diffProgram = "nvim -d";
    host.defaults.opener = "xdg-open";

  IMPORTANT: The corresponding app module must be enabled in apps-enable.nix.
  An assertion will fail if a default is set but the app module is disabled.
  (Env-only categories like pager and diffProgram are exempt.)
*/
{ config, lib, ... }:
let
  inherit (config.flake.lib) xdg;
  inherit (xdg) desktopFiles;

  categoryMeta = xdg.defaultAppCategoryMeta;
  envOnlyMeta = xdg.defaultAppEnvOnlyMeta;

  defaultAppCategories = lib.mapAttrs (
    name: meta: meta // { desktopFiles = desktopFiles.${name}; }
  ) categoryMeta;

  s76Share = config.flake.lib.nixos.hosts.system76.shareCommon;
  tpShare = config.flake.lib.nixos.hosts.tpnix.shareCommon;

  body =
    {
      config,
      lib,
      options,
      ...
    }:
    let
      cfg = config.host.defaults;
      hasHomeManager = options ? home-manager;

      mkCategoryOption =
        _name: cat:
        lib.mkOption {
          type = lib.types.nullOr (lib.types.enum (lib.attrNames cat.desktopFiles));
          default = null;
          inherit (cat) example description;
        };

      mkEnvOnlyOption =
        _name: cat:
        lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          inherit (cat) example description;
        };

      mkCategoryConfig =
        name: cat:
        lib.mkIf (cfg.${name} != null) (
          lib.mkMerge [
            { xdg.mime.defaultApplications = cat.mkMimeDefaults cat.desktopFiles.${cfg.${name}}.desktop; }
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

      mkEnvOnlyConfig = name: cat: lib.mkIf (cfg.${name} != null) (cat.extraConfig cfg.${name});

      mkCategoryAssertion =
        name: cat:
        let
          value = cfg.${name};
        in
        lib.optional (value != null) (
          let
            appInfo = cat.desktopFiles.${value};
            moduleName = appInfo.module;
            moduleExists = config.programs ? ${moduleName};
            hasExtended = moduleExists && config.programs.${moduleName} ? extended;
            hasEnable = hasExtended && config.programs.${moduleName}.extended ? enable;
            isEnabled = hasEnable && config.programs.${moduleName}.extended.enable;
          in
          {
            assertion = isEnabled;
            message =
              if !moduleExists then
                ''
                  host.defaults.${name} is set to "${value}" but the app module 'programs.${moduleName}' does not exist.
                  Create the app module or set host.defaults.${name} = null; to disable this default.
                ''
              else if !hasExtended then
                ''
                  host.defaults.${name} is set to "${value}" but 'programs.${moduleName}.extended' does not exist.
                  The app module may not follow the expected pattern.
                ''
              else if !hasEnable then
                ''
                  host.defaults.${name} is set to "${value}" but 'programs.${moduleName}.extended.enable' does not exist.
                  The app module may not follow the expected pattern.
                ''
              else
                ''
                  host.defaults.${name} is set to "${value}" but the app module is not enabled.
                  Enable it with: programs.${moduleName}.extended.enable = true;
                  Or set host.defaults.${name} = null; to disable this default.
                '';
          }
        );
    in
    {
      options.host.defaults =
        (lib.mapAttrs mkCategoryOption defaultAppCategories) // (lib.mapAttrs mkEnvOnlyOption envOnlyMeta);

      config = lib.mkMerge (
        [
          { assertions = lib.flatten (lib.mapAttrsToList mkCategoryAssertion defaultAppCategories); }
          { host.defaults = lib.mapAttrs (_: cat: lib.mkDefault cat.defaultValue) defaultAppCategories; }
          { host.defaults = lib.mapAttrs (_: cat: lib.mkDefault cat.defaultValue) envOnlyMeta; }
        ]
        ++ lib.mapAttrsToList mkCategoryConfig defaultAppCategories
        ++ lib.mapAttrsToList mkEnvOnlyConfig envOnlyMeta
      );
    };
in
{
  configurations.nixos.system76.module = lib.mkIf s76Share body;
  configurations.nixos.tpnix.module = lib.mkIf tpShare body;
}
