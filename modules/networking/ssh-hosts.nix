_: {
  # Provide per-host SSH config via include files under ~/.ssh/hosts/*
  flake.modules.homeManager.base = args: {
    home.file = {
      ".ssh/hosts/tailscale".text = ''
        Host tailscale
          Port 22
          ForwardAgent yes
          ForwardX11 yes
          User ${args.config.home.username}
          HostName 100.64.1.5
      '';

      ".ssh/hosts/github.com".text = ''
        Host github.com
          Hostname ssh.github.com
          Port 443
          User git
          IdentitiesOnly yes
      '';

      ".ssh/hosts/system76.local".text = ''
        Host system76.local
          IdentityFile ~/.ssh/id_ed25519
      '';

      ".ssh/hosts/tec.local".text = ''
        Host tec.local
          IdentityFile ~/.ssh/id_ed25519
      '';
    };
  };
}
