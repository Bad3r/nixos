{ config, ... }:
let
  fleetHostNames = builtins.attrNames (config.flake.lib.nixos.hosts or { });
in
{
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
      ] null osConfig;
      selfHostName = lib.attrByPath [ "networking" "hostName" ] "" osConfig;
      # One LAN alias per registered fleet host, excluding the host itself.
      lanAliasFiles = lib.listToAttrs (
        map (name: {
          name = ".ssh/hosts/${name}.local";
          value.text = ''
            Host ${name}.local
              IdentityFile ~/.ssh/id_ed25519
          '';
        }) (lib.filter (name: name != selfHostName) fleetHostNames)
      );
    in
    {
      home.file = lib.mkMerge [
        (lib.mkIf (tailscaleEnabled && tailscaleHostName != null) {
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
        }
        lanAliasFiles
      ];
    };
}
