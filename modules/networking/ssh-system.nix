{
  flake.modules.nixos.base = {
    programs.ssh.extraConfig = ''
      IdentityAgent /run/user/%i/gnupg/S.gpg-agent.ssh
    '';
  };
}