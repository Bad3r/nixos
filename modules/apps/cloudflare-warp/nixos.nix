/*
  Package: cloudflare-warp
  Variant: headless (warp-cli + warp-svc; no GUI taskbar, no XDG autostart)
  Description: Cloudflare WARP client delivering encrypted consumer VPN and Zero Trust connectivity.
  Homepage: https://developers.cloudflare.com/warp-client/
  Documentation: https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/cloudflare-one-client/
  Repository: https://github.com/cloudflare/warp

  Summary:
    * Runs warp-svc as a Zero Trust device enrolled with a per-host Access service token, no browser login.
    * Renders the managed deployment file (mdm.xml) from sops secrets, so the token stays on tmpfs.
    * Starts Connected at boot; the per-host mode decides whether WARP also becomes the system resolver.
    * Replaces the host's nixos-<host> device profile exclude list at boot and on every switch when it
      differs from the base list below plus the host's encrypted <host>.exclude entries, and restarts
      warp-svc while the daemon still applies another list.
    * Journals warp-svc output at its real priorities from info up, minus the IPv6 fwmark retry lines
      it repeats without an IPv6 stack.

  Options:
    enable: Whether this host enrolls and runs warp-svc (the common baseline leaves it off).
    package: WARP package; the headless build ships warp-cli, warp-svc, warp-dex, and warp-diag.
    serviceMode: mdm.xml service_mode, `warp` (Gateway with WARP, WARP owns DNS) or `tunnelonly` (traffic only).
*/
{ config, ... }:
let
  hostsRegistry = config.flake.lib.nixos.hosts or { };
  inherit (config.flake.lib.security) sopsInstallSecretsDeps;
  meshInterface = config.flake.lib.nixos._firewallMeshInterface;
  meshHostNames = builtins.filter (
    name: hostsRegistry.${name}.cloudflareWarpMeshAddressReady or false
  ) (builtins.attrNames hostsRegistry);
  # Shared with modules/apps/rustdesk/nixos.nix and modules/networking/ssh-hosts.nix
  # so they consume the same "cloudflare-warp/<key>" naming and mesh-ready host
  # list this module already computes, instead of retyping either.
  secretName = key: "cloudflare-warp/${key}";
  # The part of 100.64.0.0/10 that the two CGNAT excludes below leave in the
  # tunnel; Samba and RustDesk admit Mesh peers by it.
  meshRange = "100.96.0.0/12";
  # Cloudflare's stock split-tunnel exclude list, with 100.64.0.0/10 split
  # around the Mesh allocation so Mesh traffic stays in the tunnel
  # (modules/hosts/common/firewall.nix).
  baseExcludes =
    map (address: { inherit address; }) [
      "10.0.0.0/8"
      "169.254.0.0/16"
      "172.16.0.0/12"
      "192.0.0.0/24"
      "192.168.0.0/16"
      "224.0.0.0/24"
      "240.0.0.0/4"
      "255.255.255.255/32"
      "fc00::/7"
      "fd00::/8"
      "fe80::/10"
      "ff01::/16"
      "ff02::/16"
      "ff03::/16"
      "ff04::/16"
      "ff05::/16"
    ]
    ++ [
      {
        address = "100.64.0.0/11";
        description = "CGNAT below the Cloudflare Mesh range";
      }
      {
        address = "100.112.0.0/12";
        description = "CGNAT above the Cloudflare Mesh range";
      }
      {
        address = "239.255.255.250/32";
        description = "SSDP";
      }
    ]
    ++
      map
        (address: {
          inherit address;
          description = "Apple services";
        })
        [
          "17.57.144.0/22"
          "17.188.20.0/23"
          "17.188.128.0/18"
          "17.249.0.0/16"
          "17.252.0.0/16"
        ];

  CloudflareWarpModule =
    {
      config,
      lib,
      pkgs,
      hostName,
      secretsRoot,
      utils,
      ...
    }:
    let
      cfg = config.programs.cloudflare-warp.extended;
      hostFlags = hostsRegistry.${hostName} or { };
      secretFile = secretsRoot + "/cloudflare-warp.yaml";
      secretExists = builtins.pathExists secretFile;
      # Both halves, as every other secret consumer gates: the file arriving
      # before the age identity would activate sops.secrets with no key to
      # decrypt and fail activation mid-switch.
      enrolled = cfg.enable && (hostFlags.sopsRuntimeReady or false) && secretExists;
      meshHostSecretName = name: secretName "mesh-host-${name}";
      placeholderFor = name: config.sops.placeholder.${name};
      placeholder = key: placeholderFor (secretName key);
      meshHostSecrets = lib.listToAttrs (
        map (name: {
          name = meshHostSecretName name;
          value = {
            sopsFile = secretFile;
            format = "yaml";
            key = "mesh/hosts/${name}";
          };
        }) meshHostNames
      );
      templateName = "cloudflare-warp-mdm";
      hostsTemplateName = "cloudflare-warp-hosts";
      ensureTrailingNewline =
        value: if value == "" || lib.hasSuffix "\n" value then value else "${value}\n";
      localHostsText = lib.concatMapStrings (
        address:
        let
          names = config.networking.hosts.${address};
        in
        lib.optionalString (names != [ ]) "${address} ${lib.concatStringsSep " " names}\n"
      ) (builtins.attrNames config.networking.hosts);
      baseHostsText =
        "127.0.0.1 localhost\n"
        + lib.optionalString config.networking.enableIPv6 "::1 localhost\n"
        + localHostsText
        + ensureTrailingNewline config.networking.extraHosts;
      meshHostsText = lib.concatMapStrings (
        name: "${placeholderFor (meshHostSecretName name)} ${name}.internal\n"
      ) meshHostNames;
      installSecretsDeps = sopsInstallSecretsDeps config;
      # meshInterface is exported precisely so a rename propagates; a raw
      # interpolation instead of the real escaping rule would name a unit
      # systemd never creates for any future name containing a hyphen or
      # other systemd-escaped character.
      tunnelDevice = "${utils.escapeSystemdPath "/sys/subsystem/net/devices/${meshInterface}"}.device";
      resolvedDropIn = "/run/systemd/resolved.conf.d/cloudflare-warp.conf";
      resolvedRoute = pkgs.writeText "cloudflare-warp-resolved.conf" ''
        [Resolve]
        DNS=127.0.2.2 127.0.2.3
        Domains=~.
      '';
      # `all`, unlike `main`, exits 0 while resolved has no process to signal.
      reloadResolved = "${config.systemd.package}/bin/systemctl kill --kill-whom=all --signal=SIGHUP systemd-resolved.service";
      profileName = "nixos-${hostName}";
      secretPath = key: config.sops.secrets.${secretName key}.path;
      syncExcludes = pkgs.writeShellApplication {
        name = "cloudflare-warp-excludes";
        runtimeInputs = [
          cfg.package
          pkgs.coreutils
          pkgs.curl
          pkgs.jq
          config.systemd.package
        ];
        text = ''
          shopt -s inherit_errexit

          # A connecting warp-svc holds traffic outside the tunnel, and its
          # applied list is current only once it is Connected.
          warp_active=false
          if systemctl is-active --quiet cloudflare-warp.service; then
            warp_active=true
            for ((try = 0; ; try++)); do
              status=$(warp-cli --accept-tos -j status 2>/dev/null | jq -r '.status // empty') || status=
              [[ $status == Connected ]] && break
              if ((try == 90)); then
                echo "warp-svc did not reach Connected within 180 s, last status: $status" >&2
                exit 1
              fi
              sleep 2
            done
          fi

          api="https://api.cloudflare.com/client/v4/accounts/$(<${secretPath "account_id"})/devices"

          # The bearer header goes through a file descriptor so the token stays out of argv.
          cf() {
            local method=$1 path=$2 response
            shift 2
            response=$(curl -sS --max-time 30 -X "$method" "$@" \
              -H @<(printf 'Authorization: Bearer %s\n' "$(<${secretPath "zero_trust_api_token"})") \
              -H 'Content-Type: application/json' "$api$path")
            if ! jq -e .success <<<"$response" >/dev/null; then
              echo "$method $path failed: $(jq -c .errors <<<"$response")" >&2
              return 1
            fi
            jq -c .result <<<"$response"
          }

          want=$(jq -c --slurpfile base ${pkgs.writeText "cloudflare-warp-base-excludes.json" (builtins.toJSON baseExcludes)} \
            '$base[0] + .' ${secretPath "exclude"})
          id=$(cf GET /policies | jq -r --arg name '${profileName}' '.[] | select(.name == $name) | .policy_id')
          if [[ -z $id ]]; then
            echo "no device profile named ${profileName}" >&2
            exit 1
          fi
          have=$(cf GET "/policy/$id/exclude")
          # Cloudflare returns the list and each entry's keys in its own order;
          # jq compares objects by key, so the two compare as sets of entries.
          changes=$(jq -rs '
            def canon: map(with_entries(select(.value != null and .value != ""))) | sort;
            (.[0] | canon) as $want | (.[1] | canon) as $have
            | (($want - $have)[] | "+ \(.)"), (($have - $want)[] | "- \(.)")
          ' <<<"$want$have")
          if [[ -z $changes ]]; then
            echo "${profileName} exclude list matches the declared one"
          else
            echo "$changes"
            cf PUT "/policy/$id/exclude" --data-binary @- <<<"$want" >/dev/null
            echo "replaced the ${profileName} exclude list"
          fi

          # warp-svc can keep a previous list past Cloudflare's propagation
          # window; a daemon that is not running loads the current one at start.
          if $warp_active; then
            ips=$(warp-cli --accept-tos -j tunnel ip list)
            hosts=$(warp-cli --accept-tos -j tunnel host list)
            applied=$(jq -sc '[.[0].routes[].value, .[1].hosts[].value] | unique' <<<"$ips$hosts")
            if [[ $applied != "$(jq -c 'map(.address // .host) | unique' <<<"$want")" ]]; then
              echo "warp-svc applies a different exclude list; restarting it"
              systemctl try-restart --no-block cloudflare-warp.service
            fi
          fi
        '';
      };
    in
    {
      options.programs.cloudflare-warp.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enroll this host into Cloudflare Zero Trust with its service token and run warp-svc.";
        };

        enrolled = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Whether this host is actually enrolled: `enable` is set, its
            `flake.lib.nixos.hosts` entry reports `sopsRuntimeReady`, and
            `secrets/cloudflare-warp.yaml` exists. Mirrors the readiness gate
            that controls `/etc/hosts` rendering below, so other modules (the
            SSH mesh aliases in modules/networking/ssh-hosts.nix) can key off
            real enrollment instead of the raw `enable` flag.
          '';
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.cloudflare-warp.override { headless = true; };
          defaultText = lib.literalExpression "pkgs.cloudflare-warp.override { headless = true; }";
          description = ''
            Cloudflare WARP package. Defaults to the headless build, which
            ships `warp-cli`, `warp-svc`, `warp-dex`, and `warp-diag` and
            omits the GUI taskbar,
            `etc/xdg/autostart/com.cloudflare.WarpTaskbar.desktop`, and the
            `share/systemd/user/warp-taskbar.service` user unit. Set to
            `pkgs.cloudflare-warp` to install the GUI variant.
          '';
        };

        serviceMode = lib.mkOption {
          type = lib.types.enum [
            "warp"
            "tunnelonly"
          ];
          description = ''
            `service_mode` written to mdm.xml. `warp` (Gateway with WARP)
            makes WARP the system resolver while its tunnel is up, through
            systemd-resolved where resolved runs, and leaves the link servers
            answering whenever the tunnel is down; `tunnelonly` carries traffic
            and leaves local DNS alone. The host's device profile in the Zero
            Trust dashboard carries the same mode; the device-profile API
            spells the two `warp` and `warp_tunnel_only`, and `warp-cli mode`
            spells the second `tunnel_only`. Required whenever `enable` is
            set, since this option deliberately has no default.
          '';
        };
      };

      config = lib.mkMerge [
        { programs.cloudflare-warp.extended.enrolled = enrolled; }

        (lib.mkIf enrolled {
          assertions = [
            {
              assertion = lib.length config.networking.hostFiles == 3;
              message = "cloudflare-warp hosts rendering expects only NixOS's standard localhost, networking.hosts, and networking.extraHosts files";
            }
          ];

          services.cloudflare-warp = {
            enable = true;
            inherit (cfg) package;
            # The client only dials out; the upstream default opens inbound
            # UDP 2408 that nothing listens on.
            openFirewall = false;
            # warp-svc writes its debug stream to the journal; the files under
            # /var/log/cloudflare-warp keep it for warp-diag.
            logLevel = "info";
          };

          # The rendered file preserves NixOS's normal static mappings and adds
          # the encrypted Mesh addresses only after SOPS decrypts them.
          environment.etc.hosts.source = lib.mkForce config.sops.templates.${hostsTemplateName}.path;

          sops.secrets = {
            ${secretName "organization"} = {
              sopsFile = secretFile;
              format = "yaml";
              key = "organization";
            };
            ${secretName "auth_client_id"} = {
              sopsFile = secretFile;
              format = "yaml";
              key = "${hostName}/auth_client_id";
            };
            ${secretName "auth_client_secret"} = {
              sopsFile = secretFile;
              format = "yaml";
              key = "${hostName}/auth_client_secret";
            };
            ${secretName "account_id"} = {
              sopsFile = secretFile;
              format = "yaml";
              key = "account_id";
            };
            ${secretName "zero_trust_api_token"} = {
              sopsFile = secretFile;
              format = "yaml";
              key = "zero_trust_api_token";
            };
            # A JSON array string: sops-nix decrypts only string leaves.
            ${secretName "exclude"} = {
              sopsFile = secretFile;
              format = "yaml";
              key = "${hostName}/exclude";
            };
          }
          // meshHostSecrets;

          # A bare <dict> plist fragment: no XML declaration, no <plist>
          # wrapper. The values are hex strings and a DNS label, so nothing
          # needs escaping. auto_connect present, at 0, starts the client
          # Connected after install and reboot while a manual disconnect
          # holds until the next boot; onboarding false suppresses the
          # client's first-launch screens.
          sops.templates = {
            ${templateName} = {
              content = ''
                <dict>
                  <key>organization</key>
                  <string>${placeholder "organization"}</string>
                  <key>auth_client_id</key>
                  <string>${placeholder "auth_client_id"}</string>
                  <key>auth_client_secret</key>
                  <string>${placeholder "auth_client_secret"}</string>
                  <key>service_mode</key>
                  <string>${cfg.serviceMode}</string>
                  <key>auto_connect</key>
                  <integer>0</integer>
                  <key>onboarding</key>
                  <false/>
                </dict>
              '';
              mode = "0600";
              restartUnits = [ "cloudflare-warp.service" ];
            };

            ${hostsTemplateName} = {
              content = baseHostsText + meshHostsText;
              owner = "root";
              group = "root";
              mode = "0444";
              restartUnits = [ "nscd.service" ];
            };
          };

          systemd.services.cloudflare-warp = {
            after = installSecretsDeps;
            requires = installSecretsDeps;
            # warp-svc opens mdm.xml with O_NOFOLLOW, so the tmpfs render is
            # bind-mounted in as a regular file instead of symlinked (ELOOP).
            serviceConfig.BindReadOnlyPaths = [
              "${config.sops.templates.${templateName}.path}:${config.services.cloudflare-warp.rootDir}/mdm.xml"
            ];
            # Without an IPv6 stack, warp-svc retries its IPv6 fwmark rule every
            # 30 s and logs three lines per attempt while the IPv4 tunnel is fine.
            # The patterns match the uncolored text that logLevel turns on.
            serviceConfig.LogFilterPatterns = lib.mkIf (config.services.cloudflare-warp.logLevel != null) [
              "~WARN warp_connection::platform::desktop::linux: Reinstalling missing WARP fwmark policy rule family=IPv6$"
              "~INFO warp_tun::linux: IPv6 disabled, ignoring netlink rejection .* ipv6_disabled_source=BootCommandLine$"
              "~WARN actor_connection::network: Reinstalled missing WARP fwmark policy rules observed=Ipv4Only$"
            ];
          };

          systemd.services.cloudflare-warp-excludes = {
            description = "Replace the ${profileName} WARP exclude list when it differs from the declared one";
            wantedBy = [ "multi-user.target" ];
            wants = [ "network-online.target" ];
            after = [
              "network-online.target"
              "cloudflare-warp.service"
            ]
            ++ installSecretsDeps;
            requires = installSecretsDeps;
            # No RemainAfterExit: switch-to-configuration starts every active
            # target, which reruns this inactive oneshot, so each switch
            # reapplies the declared list and reverts dashboard edits.
            serviceConfig = {
              Type = "oneshot";
              ExecStart = lib.getExe syncExcludes;
              # A run at boot can fail before the uplink or the WARP tunnel
              # carries traffic.
              Restart = "on-failure";
              RestartSec = "5min";
            };
          };
        })

        # warp-svc cannot register with resolved on systemd 261 and writes
        # /etc/resolv.conf instead, which glibc skips while nss-resolve answers.
        # The route to the proxy lives only as long as the tunnel device, so the
        # link servers answer whenever warp-svc is stopped, disconnected, or dead.
        (lib.mkIf (enrolled && cfg.serviceMode == "warp" && config.services.resolved.enable) {
          systemd.services.cloudflare-warp-dns = {
            description = "Route systemd-resolved to the WARP DNS proxy while CloudflareWARP exists";
            bindsTo = [ tunnelDevice ];
            after = [
              tunnelDevice
              "systemd-resolved.service"
            ];
            wantedBy = [ tunnelDevice ];
            # Every tunnel transition starts the unit, so the default five starts
            # in 10 s would fail it on a flapping tunnel and leave the route off.
            startLimitIntervalSec = 0;
            # SIGHUP, not a reload job: shutdown queues resolved's stop
            # irreversibly, and a reload transaction would be refused.
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = [
                "${pkgs.coreutils}/bin/install -D -m 0644 ${resolvedRoute} ${resolvedDropIn}"
                # resolved reads the drop-in whenever it next starts, so a failed
                # reload must not fail the unit and let ExecStopPost delete the route.
                "-${reloadResolved}"
              ];
              ExecStopPost = [
                "${pkgs.coreutils}/bin/rm -f ${resolvedDropIn}"
                # resolved can already be unloaded here (late shutdown, or
                # services.resolved.enable flipped off in a later generation);
                # matching ExecStart's "-" prefix keeps that from failing this
                # unit's stop on an otherwise clean teardown.
                "-${reloadResolved}"
              ];
            };
          };
          # A tunnel already up at switch time never pulls in the unit, so a
          # changed route restarts warp-svc, whose new tunnel does.
          systemd.services.cloudflare-warp.restartTriggers = [ resolvedRoute ];
        })

        # The upstream service module installs the package only on the
        # enrolled path, and warp-cli and warp-diag stay useful for diagnosing
        # an enrollment that never came up.
        (lib.mkIf cfg.enable {
          environment.systemPackages = [ cfg.package ];
        })

        (lib.mkIf (cfg.enable && !enrolled) {
          warnings = [
            (
              if !secretExists then
                "Cloudflare WARP enrollment is disabled on ${hostName} because secrets/cloudflare-warp.yaml is missing."
              else if !(hostsRegistry ? ${hostName}) then
                "Cloudflare WARP enrollment is disabled on ${hostName} because it has no flake.lib.nixos.hosts entry; add one in modules/hosts/${hostName}/policy.nix."
              else
                "Cloudflare WARP enrollment is disabled on ${hostName} because flake.lib.nixos.hosts.${hostName}.sopsRuntimeReady is false."
            )
          ];
        })
      ];
    };
in
{
  nixpkgs.allowedUnfreePackages = [
    "cloudflare-warp"
    "cloudflare-warp-headless"
  ];

  flake = {
    lib.nixos = {
      _cloudflareWarpBaseExcludes = baseExcludes;
      _cloudflareWarpMeshHostNames = meshHostNames;
      _cloudflareWarpMeshRange = meshRange;
      _cloudflareWarpSecretName = secretName;
    };
    nixosModules.apps.cloudflare-warp = CloudflareWarpModule;
  };
}
