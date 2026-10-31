/*
  Package: frida-tools
  Description: Dynamic instrumentation toolkit for developers, reverse-engineers, and security researchers.
  Homepage: https://frida.re/
  Documentation: https://frida.re/docs/home/
  Repository: https://github.com/frida/frida-tools

  Summary:
    * Injects JavaScript into native apps on Windows, macOS, Linux, iOS, Android, and QNX.
    * Hooks functions, traces calls, and modifies behavior at runtime without source code.
*/
_:
let
  FridaToolsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.frida-tools.extended;
    in
    {
      options.programs.frida-tools.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable frida-tools dynamic instrumentation toolkit.";
        };

        package = lib.mkPackageOption pkgs "frida-tools" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."frida-tools" = FridaToolsModule;
}
