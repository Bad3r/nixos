/*
  Package: frida-tools
  Description: Dynamic instrumentation toolkit for developers, reverse-engineers, and security researchers.
  Homepage: https://frida.re/
  Documentation: https://frida.re/docs/home/
  Repository: https://github.com/frida/frida-tools

  Summary:
    * Injects JavaScript into native apps on Windows, macOS, Linux, iOS, Android, and QNX.
    * Hooks functions, traces calls, and modifies behavior at runtime without source code.

  Notes:
    * A `NOPASSWD` sudo-rs rule lets `wheel` users run `frida`, `frida-trace`, `frida-strace`, `frida-itrace`, `frida-discover` as root, which attaches to processes that `kernel.yama.ptrace_scope = 1` shields from the owner.
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

        security.sudo-rs.extraRules = [
          {
            commands = [
              {
                command = "${cfg.package}/bin/frida";
                options = [ "NOPASSWD" ];
              }
              {
                command = "${cfg.package}/bin/frida-trace";
                options = [ "NOPASSWD" ];
              }
              {
                command = "${cfg.package}/bin/frida-strace";
                options = [ "NOPASSWD" ];
              }
              {
                command = "${cfg.package}/bin/frida-itrace";
                options = [ "NOPASSWD" ];
              }
              {
                command = "${cfg.package}/bin/frida-discover";
                options = [ "NOPASSWD" ];
              }
            ];
            groups = [ "wheel" ];
          }
        ];
      };
    };
in
{
  flake.nixosModules.apps."frida-tools" = FridaToolsModule;
}
