{
  configurations.nixos.tpnix.module = {
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
}
