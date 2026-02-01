/*
  Package: frida-tools
  Description: Dynamic instrumentation toolkit for developers, reverse-engineers, and security researchers.
  Homepage: https://frida.re/
  Documentation: https://frida.re/docs/home/
  Repository: https://github.com/frida/frida

  Summary:
    * Inject JavaScript into native apps on Windows, macOS, Linux, iOS, Android, and QNX.
    * Hook functions, trace calls, modify behavior at runtime without source code.
    * Powerful for mobile app security testing, malware analysis, and debugging.

  Included Tools:
    frida: Main CLI for attaching to processes and running scripts.
    frida-ps: List running processes on local or remote systems.
    frida-trace: Trace function calls with auto-generated handlers.
    frida-discover: Discover internal functions in a process.
    frida-ls-devices: List available Frida devices (USB, remote, local).
    frida-kill: Kill a process by name or PID.

  Example Usage:
    * `frida -U com.example.app` -- Attach to iOS/Android app over USB.
    * `frida-ps -U` -- List processes on USB-connected device.
    * `frida-trace -U -i "open*" com.example.app` -- Trace open* functions.
    * `frida -U -l script.js com.example.app` -- Inject JavaScript into app.

  iOS/Android Setup:
    * iOS: Install frida-server via Cydia or sideload on jailbroken device.
    * Android: Push frida-server to /data/local/tmp and run as root.
    * Use -U flag for USB connection, -H host:port for remote.
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
