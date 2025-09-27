_: {
  flake.nixosModules.workstation = _: {
    # Preserve environment by default when using `su` (keeps SSH_AUTH_SOCK)
    environment.shellAliases.su = "su -p";

    # Be explicit: keep pam_env for su and allow SSH agent auth via PAM
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
