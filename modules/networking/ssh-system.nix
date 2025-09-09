{
  flake.nixosModules.base = {
    programs.ssh.extraConfig = ''
      IdentityAgent /run/user/%i/gnupg/S.gpg-agent.ssh
    '';
  };
}
