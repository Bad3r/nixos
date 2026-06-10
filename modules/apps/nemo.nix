/*
  Package: nemo
  Description: Cinnamon’s file manager with dual-pane browsing, tabs, and integration with GNOME virtual file systems.
  Homepage: https://github.com/linuxmint/nemo
  Documentation: https://github.com/linuxmint/nemo#readme
  Repository: https://github.com/linuxmint/nemo

  Summary:
    * Provides a feature-rich file manager supporting SMB/NFS/GVFS mounts, context-menu extensions, bulk rename, and media previews.
    * Installs video and XApp thumbnail generators so XDG thumbnail lookup can generate previews for common media formats.
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
      nemoExtensionPackages =
        lib.optional cfg.preview.enable cfg.preview.package
        ++ lib.optional cfg.seahorse.enable cfg.seahorse.package;

      configuredPackage =
        if nemoExtensionPackages == [ ] then
          cfg.package
        else if cfg.package ? override then
          cfg.package.override {
            extensions = nemoExtensionPackages;
          }
        else
          cfg.package;

      seahorseGSettingsPackages = [
        pkgs.nemo
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

        package = lib.mkPackageOption pkgs "nemo-with-extensions" { };

        preview = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to enable Nemo quick preview integration.";
          };

          package = lib.mkPackageOption pkgs "nemo-preview" { };
        };

        seahorse = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to enable Nemo Seahorse encryption and signing integration.";
          };

          package = lib.mkPackageOption pkgs "nemo-seahorse" { };
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = nemoExtensionPackages == [ ] || cfg.package ? override;
            message = "programs.nemo.extended.package requires override support when preview or seahorse integration is enabled";
          }
        ];

        environment.systemPackages = [
          configuredPackage
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
