/*
  Package: nemo
  Description: Cinnamon’s file manager with dual-pane browsing, tabs, and integration with GNOME virtual file systems.
  Homepage: https://github.com/linuxmint/nemo
  Documentation: https://github.com/linuxmint/nemo#readme
  Repository: https://github.com/linuxmint/nemo

  Summary:
    * Provides a feature-rich file manager supporting SMB/NFS/GVFS mounts, context-menu extensions, bulk rename, and media previews.
    * Enables the Mint-default Nemo extensions explicitly instead of relying on wrapper defaults.
    * Installs optional video and XApp thumbnail generators so XDG thumbnail lookup can generate previews for common media formats.
    * Enables Nemo quick previews and Seahorse encryption/signing integration by default.
    * Integrates Cinnamon desktop conventions while remaining usable in other desktop environments with underlying GNOME services.

  Options:
    nemo <path>: Open Nemo at a specified directory.
    nemo --quit: Close existing Nemo instances.
    nemo --new-window: Force opening a new window even if one is already running.
    nemo --no-desktop: Launch without managing desktop icons (useful outside Cinnamon).

  Example Usage:
    * `nemo ~/Projects` -- Browse the Projects directory in a new Nemo window.
    * `nemo --new-window smb://server/share` -- Connect to a remote SMB share.
    * `nemo --no-desktop` -- Use Nemo purely as a file manager in non-Cinnamon environments.
*/
_:
let
  NemoModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.nemo.extended;
      mkExtensionOptions = packageName: description: {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to enable ${description}.";
        };

        package = lib.mkPackageOption pkgs packageName { };
      };

      configuredExtensions = [
        cfg.folderColorSwitcher
        cfg.emblems
        cfg.fileRoller
        cfg.python
        cfg.preview
        cfg.seahorse
      ];

      nemoExtensionPackages = lib.concatMap (
        extension: lib.optional extension.enable extension.package
      ) configuredExtensions;

      canWrapPackage = cfg.package ? extensiondir && cfg.package ? version;

      configuredPackage =
        if nemoExtensionPackages == [ ] then
          cfg.package
        else if canWrapPackage then
          pkgs.nemo-with-extensions.override {
            nemo = cfg.package;
            extensions = nemoExtensionPackages;
            useDefaultExtensions = false;
          }
        else
          cfg.package;

      seahorseGSettingsPackages = [
        cfg.package
        pkgs.gcr
        pkgs.libcryptui
        cfg.seahorse.package
      ];
    in
    {
      options.programs.nemo.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable nemo.";
        };

        package = lib.mkPackageOption pkgs "nemo" { };

        folderColorSwitcher = mkExtensionOptions "folder-color-switcher" "Nemo folder color integration";

        emblems = mkExtensionOptions "nemo-emblems" "Nemo emblem integration";

        fileRoller = mkExtensionOptions "nemo-fileroller" "Nemo archive integration";

        python = mkExtensionOptions "nemo-python" "Nemo Python extension loading support";

        preview = mkExtensionOptions "nemo-preview" "Nemo quick preview integration";

        seahorse = mkExtensionOptions "nemo-seahorse" "Nemo Seahorse encryption and signing integration";

        thumbnailers.enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to install video and XApp thumbnail generators for media previews.";
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = nemoExtensionPackages == [ ] || canWrapPackage;
            message = "programs.nemo.extended.package requires version and extensiondir attributes when Nemo extensions are enabled";
          }
        ];

        environment.systemPackages = [
          configuredPackage
        ]
        ++ lib.optionals cfg.thumbnailers.enable [
          pkgs.ffmpegthumbnailer
          pkgs.gst-thumbnailers
          pkgs.xapp-thumbnailers
        ];

        services = {
          dbus.packages = [
            configuredPackage
          ]
          ++ lib.optionals cfg.seahorse.enable [
            pkgs.libcryptui
          ];

          desktopManager.gnome.extraGSettingsOverridePackages = lib.optionals cfg.seahorse.enable seahorseGSettingsPackages;

          xserver.desktopManager.cinnamon.extraGSettingsOverridePackages = lib.optionals cfg.seahorse.enable seahorseGSettingsPackages;
        };
      };
    };
in
{
  flake.nixosModules.apps.nemo = NemoModule;
}
