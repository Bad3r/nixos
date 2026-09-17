{ config, lib, ... }:
let
  fleetIdentityPath = "~/.ssh/keys/onepassword-ssh.pub";
  gitSigningIdentityPath = "~/.ssh/keys/onepassword-git-signing.pub";

  githubHostConfig = ''
    Host github.com
      Hostname ssh.github.com
      Port 443
      User git
      IdentitiesOnly yes
      IdentityFile ${gitSigningIdentityPath}
      ForwardAgent no
      # Reuse SSH connection for GitHub only
      ControlMaster auto
      ControlPersist 15m
      ControlPath ~/.ssh/ctl-%C
  '';

  formatCaseFailures =
    config.flake.lib.nixos._formatCheckFailures
      or (throw "modules/lib/check-failures.nix no longer exports flake.lib.nixos._formatCheckFailures");

  meshAliasFilesFor =
    {
      meshHostNames,
      fleetHostKeys,
      warpEnabled,
      selfHostName,
      username,
      onePasswordSshAgentEnabled,
    }:
    let
      # ~/.1password/agent.sock is created at runtime by the 1Password
      # desktop app (GUI); gating on it, matching modules/networking/ssh.nix,
      # keeps this from pointing IdentityAgent at a socket that never exists
      # and silently breaking SSH authentication.
      identityLines =
        if onePasswordSshAgentEnabled then
          "  IdentityAgent ~/.1password/agent.sock\n  IdentityFile ${fleetIdentityPath}\n"
        else
          "  IdentityFile ~/.ssh/id_ed25519\n";
    in
    lib.optionalAttrs warpEnabled (
      lib.listToAttrs (
        map (name: {
          name = ".ssh/hosts/${name}.internal";
          value.text = ''
            Host ${name}.internal
              Port 22
              ForwardAgent no
              ForwardX11 yes
              User ${username}
              IdentitiesOnly yes
          ''
          + identityLines;
        }) (builtins.filter (name: name != selfHostName && fleetHostKeys ? ${name}) meshHostNames)
      )
    );

  sshHostsModule =
    registry:
    {
      lib,
      metaOwner,
      osConfig,
      ...
    }:
    let
      inherit (registry) hostNames meshHostNames fleetHostKeys;
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
        "enrolled"
      ] false osConfig;
      # ~/.1password/agent.sock is created at runtime by the 1Password
      # desktop app (GUI); gating on it, matching modules/networking/ssh.nix,
      # keeps the aliases below from pointing IdentityAgent/IdentityFile at a
      # socket or key that never exists.
      onePasswordSshAgentEnabled = lib.attrByPath [
        "programs"
        "1password-gui-beta"
        "extended"
        "enable"
      ] false osConfig;
      selfHostName = lib.attrByPath [ "networking" "hostName" ] "" osConfig;
      lanAliasFiles = lib.listToAttrs (
        map (name: {
          name = ".ssh/hosts/${name}.local";
          value.text = ''
            Host ${name}.local
              IdentityFile ${if onePasswordSshAgentEnabled then fleetIdentityPath else "~/.ssh/id_ed25519"}
          '';
        }) (lib.filter (name: name != selfHostName) hostNames)
      );
      meshAliasFiles = meshAliasFilesFor {
        inherit
          fleetHostKeys
          meshHostNames
          onePasswordSshAgentEnabled
          selfHostName
          warpEnabled
          ;
        inherit (metaOwner) username;
      };
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
          ".ssh/keys/onepassword-ssh.pub".text = ''
            ${metaOwner.fleetSshPublicKey}
          '';
          ".ssh/keys/onepassword-git-signing.pub".text = ''
            ${metaOwner.gitSigningPublicKey}
          '';
          ".ssh/hosts/github.com".text = githubHostConfig;
        }
        lanAliasFiles
        meshAliasFiles
      ];
    };

  fixture = {
    meshHostNames = [
      "self"
      "alpha"
      "unpinned"
    ];
    fleetHostKeys = {
      self = "ssh-ed25519 fixture-self";
      alpha = "ssh-ed25519 fixture-alpha";
    };
    selfHostName = "self";
    username = "owner";
    onePasswordSshAgentEnabled = true;
  };
  meshOn = meshAliasFilesFor (fixture // { warpEnabled = true; });
  meshOff = meshAliasFilesFor (fixture // { warpEnabled = false; });
  alphaAlias = meshOn.".ssh/hosts/alpha.internal".text or "";
  githubAlias = githubHostConfig;
  meshAliasFailures =
    lib.optional (
      builtins.attrNames meshOn != [ ".ssh/hosts/alpha.internal" ]
    ) "WARP enabled: got ${builtins.toJSON (builtins.attrNames meshOn)}, expected only alpha.internal"
    ++ lib.optional (
      !lib.hasInfix "Host alpha.internal" alphaAlias
    ) "alpha.internal: missing Host pattern"
    ++ lib.optional (lib.hasInfix "HostName" alphaAlias) "alpha.internal: embeds a build-time address"
    ++ lib.optional (
      !lib.hasInfix "IdentityAgent ~/.1password/agent.sock" alphaAlias
    ) "alpha.internal: does not use the 1Password SSH agent"
    ++ lib.optional (
      !lib.hasInfix "IdentityFile ~/.ssh/keys/onepassword-ssh.pub" alphaAlias
    ) "alpha.internal: does not select the SSH authentication key"
    ++ lib.optional (
      !lib.hasInfix "ForwardAgent no" alphaAlias
    ) "alpha.internal: forwards the 1Password SSH agent"
    ++ lib.optional (
      !lib.hasInfix "IdentityFile ${gitSigningIdentityPath}" githubAlias
    ) "github.com: does not select the Git signing key for SSH authentication"
    ++ lib.optional (lib.hasInfix "IdentityFile ${fleetIdentityPath}" githubAlias) "github.com: selects the fleet SSH key"
    ++ lib.optional (
      !lib.hasInfix "ForwardAgent no" githubAlias
    ) "github.com: forwards the 1Password SSH agent"
    ++ lib.optional (
      meshOff != { }
    ) "WARP disabled: rendered ${builtins.toJSON (builtins.attrNames meshOff)}";
in
{
  flake.homeManagerModules.base = sshHostsModule {
    hostNames = builtins.attrNames (config.flake.lib.nixos.hosts or { });
    meshHostNames = config.flake.lib.nixos._cloudflareWarpMeshHostNames or [ ];
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
