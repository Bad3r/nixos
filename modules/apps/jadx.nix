/*
  Package: jadx
  Description: Dex to Java decompiler with command-line and GUI tools.
  Homepage: https://github.com/skylot/jadx
  Repository: https://github.com/skylot/jadx

  Summary:
    * Decompile Android DEX and APK files to Java source code.
    * GUI for interactive exploration of decompiled code.
    * CLI for batch processing and automation.

  Included Tools:
    jadx: Command-line interface for decompiling DEX/APK files.
    jadx-gui: Graphical interface for browsing decompiled sources.

  Example Usage:
    * `jadx app.apk` -- Decompile APK to Java sources in ./app directory.
    * `jadx -d output/ classes.dex` -- Decompile DEX to specified output directory.
    * `jadx-gui app.apk` -- Open APK in GUI for interactive analysis.
    * `jadx --deobf app.apk` -- Decompile with deobfuscation enabled.
*/
_:
let
  JadxModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.jadx.extended;
    in
    {
      options.programs.jadx.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable jadx DEX to Java decompiler.";
        };

        package = lib.mkPackageOption pkgs "jadx" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.jadx = JadxModule;
}
