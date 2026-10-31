/*
  Package: android-studio
  Description: Official IDE for Android application development with AVD support.
  Homepage: https://developer.android.com/studio
  Documentation: https://developer.android.com/studio/intro
  Repository: https://android.googlesource.com/platform/tools/adt/idea

  Summary:
    * Provides the complete Android development environment including SDK Manager and AVD Manager.

  Options:
    -Xmx4g: Increase maximum JVM heap size (useful for large projects).
    -Didea.log.path=<path>: Override the IDE log directory location.

  Notes:
    * Install cmdline-tools in the SDK Manager before using `sdkmanager`.
    * Emulator GPU fallback: `-gpu swiftshader_indirect`.
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
