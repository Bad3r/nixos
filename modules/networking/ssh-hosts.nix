_: {
  # Provide per-host SSH config via include files under ~/.ssh/hosts/*
  flake.homeManagerModules.base =
    {
      lib,
      metaOwner,
      osConfig,
      ...
    }:
    let
      tailscaleEnabled = lib.attrByPath [ "programs" "tailscale" "extended" "enable" ] false osConfig;
      tailscaleHostAlias = lib.attrByPath [
        "programs"
        "tailscale"
        "extended"
        "sshHostAlias"
      ] "tailscale" osConfig;
      tailscaleHostName = lib.attrByPath [
        "programs"
        "tailscale"
        "extended"
        "sshHostName"
      ] "100.64.1.5" osConfig;
    in
    {
      home.file = lib.mkMerge [
        (lib.mkIf tailscaleEnabled {
          ".ssh/hosts/${tailscaleHostAlias}".text = ''
            Host ${tailscaleHostAlias}
              Port 22
              ForwardAgent yes
              ForwardX11 yes
              User ${metaOwner.username}
              HostName ${tailscaleHostName}
          '';
        })
        {
          ".ssh/hosts/github.com".text = ''
            Host github.com
              Hostname ssh.github.com
              Port 443
              User git
              IdentitiesOnly yes
              # Reuse SSH connection for GitHub only
              ControlMaster auto
              ControlPersist 15m
              ControlPath ~/.ssh/ctl-%C
          '';

          ".ssh/hosts/system76.local".text = ''
            Host system76.local
              IdentityFile ~/.ssh/id_ed25519
          '';
        }
      ];
    };
}
