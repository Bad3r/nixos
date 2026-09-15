{ config, lib, ... }:
let
  formatCaseFailures =
    config.flake.lib.nixos._formatCheckFailures
      or (throw "modules/lib/check-failures.nix no longer exports flake.lib.nixos._formatCheckFailures");
  # Hosts that recorded their Cloudflare Mesh device address (meshIp in
  # modules/<host>/policy.nix) after enrolling through
  # modules/apps/cloudflare-warp.nix. One address under two hosts would point
  # one alias at the other machine while OpenSSH accepts either pinned key, and
  # an address without a fleetHostKeys pin (modules/hosts/common/ssh-known-hosts.nix)
  # would trust the first key met in a pool every team device draws from.
  meshHostNamesFor =
    {
      hostNames,
      meshIpOf,
      fleetHostKeys,
    }:
    let
      recorded = builtins.filter (name: meshIpOf name != null) hostNames;
      shared = lib.filterAttrs (_: names: lib.length names > 1) (lib.groupBy meshIpOf recorded);
      unpinned = builtins.filter (name: !(fleetHostKeys ? ${name})) recorded;
    in
    if shared != { } then
      throw "flake.lib.nixos.hosts records the same meshIp for more than one host: ${
        lib.concatStringsSep "; " (
          lib.mapAttrsToList (address: names: "${address} (${lib.concatStringsSep ", " names})") shared
        )
      }"
    else if unpinned != [ ] then
      throw "flake.lib.nixos.hosts records a meshIp for ${lib.concatStringsSep ", " unpinned} without a fleetHostKeys pin in modules/hosts/common/ssh-known-hosts.nix; pin the host key first"
    else
      recorded;

  sshHostsModule =
    registry:
    {
      lib,
      metaOwner,
      osConfig,
      ...
    }:
    let
      inherit (registry) hostNames meshIpOf;
      meshHostNames = meshHostNamesFor registry;
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
        }) (lib.filter (name: name != selfHostName) hostNames)
      );
      # One Mesh alias per fleet host with a recorded address, excluding the
      # host itself, and only on a host that runs WARP: without the tunnel
      # there is no route to 100.96.0.0/12, so the alias would hang until the
      # TCP connect times out instead of failing on an unknown host name.
      # Rendered at build time: every host switches after a meshIp lands, as
      # with any registry change. Forced outside the warpEnabled gate because
      # modules/hosts/common/ssh-known-hosts.nix pins the address on every
      # fleet host, so a refused address fails evaluation with WARP off too.
      meshAliasFiles = builtins.seq meshHostNames (
        lib.optionalAttrs warpEnabled (
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

  # The real registry satisfies both guards, so only fixture registries prove
  # they still fire; "throws" marks an evaluation the guards refuse.
  meshAliasNamesFor =
    {
      hosts,
      warp,
      pinned ? builtins.attrNames hosts,
      ...
    }:
    let
      module = sshHostsModule {
        hostNames = builtins.attrNames hosts;
        meshIpOf = name: hosts.${name}.meshIp or null;
        fleetHostKeys = lib.genAttrs pinned (_: "ssh-ed25519 fixture");
      };
      files =
        (module {
          inherit lib;
          metaOwner.username = "owner";
          osConfig = {
            programs.cloudflare-warp.extended.enable = warp;
            networking.hostName = "self";
          };
        }).home.file.contents;
      # A mkMerge participant is either a plain attrset or an mkIf wrapper
      # ({ _type = "if"; condition; content; }); reading .content without
      # checking .condition would count a false-gated entry's keys as rendered,
      # unlike the real Home Manager module system, which drops them.
      attrsOf =
        part: if (part._type or null) == "if" then (if part.condition then part.content else { }) else part;
      names = lib.concatMap (part: builtins.attrNames (attrsOf part)) files;
      result = builtins.tryEval (builtins.deepSeq names names);
    in
    if result.success then lib.filter (lib.hasSuffix ".warp") result.value else "throws";
  meshAliasCases = [
    {
      name = "distinct addresses";
      hosts = {
        self.meshIp = "100.96.0.1";
        alpha.meshIp = "100.96.0.2";
        beta = { };
      };
      warp = true;
      expected = [ ".ssh/hosts/alpha.warp" ];
    }
    {
      name = "WARP off renders no Mesh alias";
      hosts = {
        self.meshIp = "100.96.0.1";
        alpha.meshIp = "100.96.0.2";
      };
      warp = false;
      expected = [ ];
    }
    {
      name = "shared address";
      hosts = {
        self = { };
        alpha.meshIp = "100.96.0.2";
        beta.meshIp = "100.96.0.2";
      };
      warp = true;
      expected = "throws";
    }
    {
      name = "shared address with WARP off";
      hosts = {
        self = { };
        alpha.meshIp = "100.96.0.2";
        beta.meshIp = "100.96.0.2";
      };
      warp = false;
      expected = "throws";
    }
    {
      name = "two of three hosts sharing";
      hosts = {
        self.meshIp = "100.96.0.1";
        alpha.meshIp = "100.96.0.2";
        beta.meshIp = "100.96.0.2";
      };
      warp = true;
      expected = "throws";
    }
    {
      name = "address without a pin";
      hosts = {
        self = { };
        alpha.meshIp = "100.96.0.2";
      };
      warp = true;
      pinned = [ "self" ];
      expected = "throws";
    }
    {
      name = "address without a pin with WARP off";
      hosts = {
        self = { };
        alpha.meshIp = "100.96.0.2";
      };
      warp = false;
      pinned = [ "self" ];
      expected = "throws";
    }
    {
      name = "host without an address needs no pin";
      hosts = {
        self = { };
        alpha = { };
      };
      warp = true;
      pinned = [ ];
      expected = [ ];
    }
  ];
  meshAliasFailures = lib.concatMap (
    case:
    let
      got = meshAliasNamesFor case;
    in
    lib.optional (
      got != case.expected
    ) "${case.name}: got ${builtins.toJSON got}, expected ${builtins.toJSON case.expected}"
  ) meshAliasCases;
in
{
  # Provide per-host SSH config via include files under ~/.ssh/hosts/*
  flake.homeManagerModules.base = sshHostsModule {
    hostNames = builtins.attrNames (config.flake.lib.nixos.hosts or { });
    meshIpOf = config.flake.lib.nixos.meshIpOf;
    fleetHostKeys = config.flake.lib.nixos.fleetHostKeys;
  };

  perSystem =
    { pkgs, ... }:
    {
      checks.ssh-hosts-mesh-aliases =
        if meshAliasFailures != [ ] then
          throw (formatCaseFailures "ssh-hosts-mesh-aliases" meshAliasFailures)
        else
          pkgs.runCommandLocal "ssh-hosts-mesh-aliases-ok" { } "touch $out";
    };
}
