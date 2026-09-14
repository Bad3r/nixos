{ config, lib, ... }:
let
  fleetHostNames = builtins.attrNames (config.flake.lib.nixos.hosts or { });
  # Hosts that recorded their Cloudflare Mesh device address (meshIp in
  # modules/<host>/policy.nix) after enrolling through
  # modules/apps/cloudflare-warp.nix.
  meshIpOf = config.flake.lib.nixos.meshIpOf;
  recordedMeshHostNames = builtins.filter (name: meshIpOf name != null) fleetHostNames;
  # One address under two hosts would point one alias at the other machine,
  # and OpenSSH accepts either pinned key for that address
  # (modules/hosts/common/ssh-known-hosts.nix), so no mismatch warns.
  sharedMeshIps = lib.filterAttrs (_: names: lib.length names > 1) (
    lib.groupBy meshIpOf recordedMeshHostNames
  );
  meshHostNames =
    if sharedMeshIps == { } then
      recordedMeshHostNames
    else
      throw "flake.lib.nixos.hosts records the same meshIp for more than one host: ${
        lib.concatStringsSep "; " (
          lib.mapAttrsToList (address: names: "${address} (${lib.concatStringsSep ", " names})") sharedMeshIps
        )
      }";
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
      warpEnabled = lib.attrByPath [
        "programs"
        "cloudflare-warp"
        "extended"
        "enable"
      ] false osConfig;
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
      # One Mesh alias per fleet host with a recorded address, excluding the
      # host itself, and only on a host that runs WARP: without the tunnel
      # there is no route to 100.96.0.0/12, so the alias would hang until the
      # TCP connect times out instead of failing on an unknown host name.
      # Rendered at build time: every host switches after a meshIp lands, as
      # with any registry change.
      meshAliasFiles = lib.optionalAttrs warpEnabled (
        lib.listToAttrs (
          map (name: {
            name = ".ssh/hosts/${name}.warp";
            value.text = ''
              Host ${name}.warp
                HostName ${meshIpOf name}
                Port 22
                ForwardAgent yes
                ForwardX11 yes
                User ${metaOwner.username}
            '';
          }) (lib.filter (name: name != selfHostName) meshHostNames)
        )
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
        meshAliasFiles
      ];
    };
}
