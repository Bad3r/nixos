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
    msfvenom -p <payload> -f <format>: Generate payload binaries or shellcode.
    msfconsole -r <resource.rc>: Execute scripted workflows via resource files.
*/

_:
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
          default = false;
          description = "Whether to enable Metasploit Framework.";
        };

        package = lib.mkPackageOption pkgs "metasploit" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.metasploit = MetasploitModule;
}
