{ lib, ... }:
{
  flake.nixosModules.roles.system.security.imports = lib.mkAfter [
    (_: {
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
    })
  ];
}
