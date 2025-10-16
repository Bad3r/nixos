{ lib, ... }:
let
  suModule = _: {
    environment.shellAliases.su = "su -p";
    security.pam.services = {
      su = {
        setEnvironment = true;
        sshAgentAuth = true;
      };
      su-l = {
        setEnvironment = true;
        sshAgentAuth = true;
      };
    };
  };
in
{
  flake.lib.roleExtras = lib.mkAfter [
    {
      role = "system.security";
      modules = [ suModule ];
    }
  ];
}
