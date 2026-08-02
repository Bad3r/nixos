# Secret-backed DNS host pinning. Per-host data comes from the registry:
#   flake.lib.nixos.hosts.<host>.privateDnsHostsSecretKeys
#     Keys in secrets/<host>.yaml, each holding a hosts(5) payload that
#     NetworkManager's dnsmasq serves as an addn-hosts file. Name-to-IP
#     mappings for internal hosts stay out of the public system config.
{ config, lib, ... }:
let
  hostsRegistry = config.flake.lib.nixos.hosts or { };
  inherit (config.flake.lib.security) sopsInstallSecretsDeps;

  confName = "NetworkManager/dnsmasq.d/private-hosts.conf";
  # NetworkManager spawns dnsmasq without --user (nm-dns-dnsmasq.c), so the
  # privilege-drop identity comes from dnsmasq config. Pinning it here makes
  # the secret's group grant deterministic instead of relying on dnsmasq's
  # compiled-in nobody/dip defaults. Bus-policy neutral: dnsmasq's dbus_init()
  # owns org.freedesktop.NetworkManager.dnsmasq as root before setuid(), so the
  # name stays under NetworkManager's root-scoped policy grant.
  runtimeUser = "nm-dnsmasq";

  # Path component the secret name is built from. sops-nix names stay
  # hyphenated, so the fold is not injective.
  keyComponent = key: lib.replaceStrings [ "_" ] [ "-" ] key;

  # Keys sharing a component with another key. Both consumers lose data on a
  # collision: listToAttrs keeps only the last secret, and the duplicate
  # addn-hosts= line points at it, so one payload is never decrypted and never
  # served. Exported so private-dns-hosts-checks.nix covers the shipped
  # expression instead of a copy of it.
  collidingKeysOf =
    keys:
    let
      components = map keyComponent keys;
    in
    lib.filter (key: lib.count (component: component == keyComponent key) components > 1) keys;

  body =
    {
      config,
      lib,
      hostName,
      secretsRoot,
      ...
    }:
    let
      hostFlags = hostsRegistry.${hostName} or { };
      secretKeys = hostFlags.privateDnsHostsSecretKeys or [ ];
      secretFile = secretsRoot + "/${hostName}.yaml";
      declared = secretKeys != [ ];
      ready = declared && (hostFlags.sopsRuntimeReady or false) && builtins.pathExists secretFile;

      secretName = key: "${hostName}/networking/private-hosts/${keyComponent key}";
      secretPath = key: "/run/secrets/${secretName key}";
      installSecretsDeps = sopsInstallSecretsDeps config;

      collidingKeys = collidingKeysOf secretKeys;
    in
    {
      config = lib.mkMerge [
        (lib.mkIf declared {
          assertions = [
            {
              assertion = collidingKeys == [ ];
              message = "${hostName}: privateDnsHostsSecretKeys entries collide after the underscore-to-hyphen rewrite; rename one of ${lib.concatStringsSep ", " collidingKeys}.";
            }
          ];
        })

        (lib.mkIf ready {
          # addn-hosts accepts repeats, so each key stays a separate file.
          environment.etc.${confName}.text = ''
            user=${runtimeUser}
            group=${runtimeUser}
          ''
          + lib.concatMapStrings (key: "addn-hosts=${secretPath key}\n") secretKeys;

          networking.networkmanager.dns = "dnsmasq";

          users.groups.${runtimeUser} = { };
          users.users.${runtimeUser} = {
            isSystemUser = true;
            group = runtimeUser;
            description = "NetworkManager dnsmasq runtime user";
          };

          # services.resolved force-sets networking.networkmanager.dns =
          # "systemd-resolved", which conflicts with dnsmasq mode above.
          services.resolved.enable = false;

          sops.secrets = lib.listToAttrs (
            map (
              key:
              lib.nameValuePair (secretName key) {
                sopsFile = secretFile;
                format = "yaml";
                inherit key;
                path = secretPath key;
                owner = "root";
                group = runtimeUser;
                mode = "0440";
                restartUnits = [ "NetworkManager.service" ];
              }
            ) secretKeys
          );

          systemd.services.NetworkManager = {
            after = installSecretsDeps;
            requires = installSecretsDeps;
            # sops-nix restartUnits only fires when decrypted secret bytes
            # change, and environment.etc entries are not restart triggers on
            # their own, so a switch that edits the conf snippet alone would
            # leave dnsmasq running under its previous privilege-drop identity.
            # The ownership triple is triggered too: dnsmasq loads addn-hosts
            # only at startup and on SIGHUP, so a permissions-only edit that
            # restores access would otherwise not reach the running process.
            restartTriggers = [
              config.environment.etc.${confName}.source
            ]
            ++ map (
              key:
              let
                secret = config.sops.secrets.${secretName key};
              in
              "${secret.owner}:${secret.group}:${secret.mode}"
            ) secretKeys;
          };
        })

        (lib.mkIf (declared && !ready) {
          warnings = [
            "Private DNS host pinning is disabled on ${hostName} until SOPS decryption keys and secrets/${hostName}.yaml are available."
          ];
        })
      ];
    };
in
{
  flake = {
    lib.nixos._privateDnsCollidingKeysOf = collidingKeysOf;
    nixosModules.hosts-common.imports = [ body ];
  };
}
