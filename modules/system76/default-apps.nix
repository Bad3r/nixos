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
    system76.defaults.videoPlayer = "mpv";

  To switch defaults, change these settings - no need to modify
  individual app modules.
*/
{ config, ... }:
let
  inherit (config.flake.lib) xdg;

  # All default app categories with their configuration
  # Each category defines: desktopFiles mapping, MIME helper, default value, and metadata
  defaultAppCategories = {
    browser = {
      desktopFiles = {
        brave = "brave-browser.desktop";
        chrome = "google-chrome.desktop";
        chromium = "chromium-browser.desktop";
        firefox = "firefox.desktop";
        floorp = "floorp.desktop";
        librewolf = "librewolf.desktop";
        mullvad = "mullvad-browser.desktop";
        tor = "torbrowser.desktop";
        ungoogled-chromium = "chromium-browser.desktop";
      };
      mkMimeDefaults = xdg.mime.mkBrowserDefaults;
      defaultValue = "floorp";
      example = "floorp";
      description = ''
        Default web browser for this host.
        Set to null to not configure a default browser via XDG mimeapps.
      '';
    };

    terminal = {
      desktopFiles = {
        alacritty = "Alacritty.desktop";
        kitty = "kitty.desktop";
        wezterm = "org.wezfurlong.wezterm.desktop";
      };
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
      desktopFiles = {
        dolphin = "org.kde.dolphin.desktop";
        nemo = "nemo.desktop";
        nautilus = "org.gnome.Nautilus.desktop";
        thunar = "thunar.desktop";
      };
      mkMimeDefaults = xdg.mime.mkFileManagerDefaults;
      defaultValue = "nemo";
      example = "nemo";
      description = ''
        Default file manager for this host.
        Set to null to not configure a default file manager via XDG mimeapps.
      '';
    };

    imageViewer = {
      desktopFiles = {
        feh = "feh.desktop";
        gwenview = "org.kde.gwenview.desktop";
        nsxiv = "nsxiv.desktop";
        sxiv = "sxiv.desktop";
      };
      mkMimeDefaults = xdg.mime.mkImageViewerDefaults;
      defaultValue = "nsxiv";
      example = "nsxiv";
      description = ''
        Default image viewer for this host.
        Set to null to not configure a default image viewer via XDG mimeapps.
      '';
    };

    documentViewer = {
      desktopFiles = {
        evince = "org.gnome.Evince.desktop";
        okular = "org.kde.okular.desktop";
        zathura = "org.pwmt.zathura.desktop";
      };
      mkMimeDefaults = xdg.mime.mkDocumentViewerDefaults;
      defaultValue = "zathura";
      example = "zathura";
      description = ''
        Default document viewer (PDF, EPUB, DjVu, etc.) for this host.
        Set to null to not configure a default document viewer via XDG mimeapps.
      '';
    };

    videoPlayer = {
      desktopFiles = {
        mpv = "mpv.desktop";
        vlc = "vlc.desktop";
      };
      mkMimeDefaults = xdg.mime.mkVideoPlayerDefaults;
      defaultValue = "mpv";
      example = "mpv";
      description = ''
        Default video player for this host.
        Set to null to not configure a default video player via XDG mimeapps.
      '';
    };
  };
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
              xdg.mime.defaultApplications = cat.mkMimeDefaults cat.desktopFiles.${cfg.${name}};
              home-manager.sharedModules = [
                {
                  xdg.mimeApps = {
                    enable = true;
                    defaultApplications = cat.mkMimeDefaults cat.desktopFiles.${cfg.${name}};
                  };
                }
              ];
            }
            (if cat ? extraConfig then cat.extraConfig cfg.${name} else { })
          ]
        );
    in
    {
      options.system76.defaults = lib.mapAttrs mkCategoryOption defaultAppCategories;

      config = lib.mkMerge (
        # Set sensible defaults for all categories
        [
          {
            system76.defaults = lib.mapAttrs (_: cat: lib.mkDefault cat.defaultValue) defaultAppCategories;
          }
        ]
        # Generate config blocks for each category
        ++ lib.mapAttrsToList mkCategoryConfig defaultAppCategories
      );
    };
}
