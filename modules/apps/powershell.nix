/*
  Package: powershell
  Description: Powerful cross-platform (Windows, Linux, and macOS) shell and scripting language based on .NET.
  Homepage: https://microsoft.com/PowerShell
  Documentation: https://learn.microsoft.com/en-us/powershell/
  Repository: https://github.com/PowerShell/PowerShell

  Summary:
    * Provides a cross-platform shell and scripting language for automation and configuration.
    * Works with structured data, REST APIs, object models, and existing command-line tools.

  Options:
    -Command: Execute a command, script block, or command string.
    -File: Run a PowerShell script file.
    -NoProfile: Start without loading PowerShell profiles.
    -NonInteractive: Disable prompts that require user input.
*/
_:
let
  PowershellModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.powershell.extended;
    in
    {
      options.programs.powershell.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable powershell.";
        };

        package = lib.mkPackageOption pkgs "powershell" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.powershell = PowershellModule;
}
