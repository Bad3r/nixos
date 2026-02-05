/*
  Package: android-studio
  Description: Official IDE for Android application development with AVD support.
  Homepage: https://developer.android.com/studio
  Documentation: https://developer.android.com/studio/intro
  Repository: https://github.com/nicokosi/android-studio

  Summary:
    * Provides the complete Android development environment including SDK Manager and AVD Manager.
    * Enables ADB debugging and configures KVM acceleration for Android emulator.
    * Sets ANDROID_HOME and adds SDK tools to PATH for CLI access.

  Options:
    -Xmx4g: Increase maximum JVM heap size (useful for large projects).
    -Didea.log.path=<path>: Override the IDE log directory location.

  Notes:
    * Requires KVM for hardware-accelerated emulation; user is added to kvm group.
    * Use `-gpu swiftshader_indirect` with emulator if GPU acceleration causes issues.
    * Standalone adb provided via android-tools; systemd 258+ handles uaccess rules automatically.
    * Install cmdline-tools via Android Studio SDK Manager before using sdkmanager CLI.
    * Emulator requires nix-ld libraries defined in modules/system76/nix-ld.nix (libcxx, libtiff,
      libuuid, libbsd, ncurses5, X11 libs, libpulseaudio, libpng, etc.).
*/
_:
let
  AndroidStudioModule =
    {
      config,
      lib,
      pkgs,
      metaOwner,
      ...
    }:
    let
      cfg = config.programs.android-studio.extended;
      owner = metaOwner.username;
    in
    {
      options.programs.android-studio.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Android Studio.";
        };

        package = lib.mkPackageOption pkgs "android-studio" { };

        enableAdb = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to install standalone ADB (Android Debug Bridge) tools.";
        };

        androidHome = lib.mkOption {
          type = lib.types.str;
          default = "$HOME/Android/Sdk";
          description = "Path to Android SDK directory (ANDROID_HOME).";
        };
      };

      config = lib.mkIf cfg.enable {
        environment = {
          systemPackages = [ cfg.package ] ++ lib.optionals cfg.enableAdb [ pkgs.android-tools ];

          sessionVariables = {
            ANDROID_HOME = cfg.androidHome;
            ANDROID_SDK_ROOT = cfg.androidHome;
            ANDROID_AVD_HOME = "$HOME/.config/.android/avd";
          };

          shellInit = ''
            # Android SDK tools paths
            export PATH="$PATH:${cfg.androidHome}/cmdline-tools/latest/bin"
            export PATH="$PATH:${cfg.androidHome}/platform-tools"
            export PATH="$PATH:${cfg.androidHome}/emulator"
          '';
        };

        users.users.${owner}.extraGroups = lib.mkAfter [ "kvm" ];
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "android-studio" ];
  flake.nixosModules.apps.android-studio = AndroidStudioModule;
}
