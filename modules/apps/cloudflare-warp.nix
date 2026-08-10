/*
  Package: cloudflare-warp
  Variant: headless (warp-cli + warp-svc + warp-dex + warp-diag; no GUI taskbar)
  Description: Cloudflare WARP client delivering encrypted VPN and Zero Trust connectivity.
  Homepage: https://developers.cloudflare.com/warp-client/
  Documentation: https://developers.cloudflare.com/cloudflare-one/connections/connect-devices/warp/
  Repository: https://github.com/cloudflare/warp

  Summary:
    * Drives upstream services.cloudflare-warp to run warp-svc and enroll the device into
      Cloudflare Zero Trust non-interactively via a service token in managed (mdm.xml) mode.
    * Renders /var/lib/cloudflare-warp/mdm.xml from sops-backed credentials, store-safe.

  Options:
    enable: Install warp-cli; warp-svc runs only once secrets/cloudflare-warp.yaml supplies credentials.
    serviceMode: mdm.xml service_mode (warp | tunnelonly | 1dot1 | proxy | postureonly).
    autoConnect: mdm.xml auto_connect minutes (0-1440); 0 keeps the client off after a manual disconnect.
    switchLocked: mdm.xml switch_locked; when true the user cannot disconnect.
    connectOnBoot: run a best-effort oneshot that verifies managed registration before connecting.

  Notes:
    * service_mode is authoritative via mdm.xml; the module never calls `warp-cli mode`.
    * Secrets (organization/auth_client_id/auth_client_secret) live in secrets/cloudflare-warp.yaml (sops).
    * Without those credentials warp-svc would hold CAP_NET_ADMIN and an open UDP port while
      serving only consumer WARP, so an un-enrolled host installs the CLI and no daemon.
    * Relies on the hosts-common vpn-defaults owner for networking.firewall.checkReversePath;
      the WARP interface trips strict rp_filter when that shared baseline is overridden.
    * Pairs with per-host enablement in modules/tpnix/cloudflare-warp.nix and modules/system76/cloudflare-warp.nix.
*/
{ config, ... }:
let
  inherit (config.flake.lib.security) sopsInstallSecretsDeps;
  CloudflareWarpModule =
    {
      config,
      lib,
      pkgs,
      secretsRoot,
      ...
    }:
    let
      cfg = config.programs.cloudflare-warp.extended;
      rootDir = config.services.cloudflare-warp.rootDir;
      secretsFile = secretsRoot + "/cloudflare-warp.yaml";
      enrolling = builtins.pathExists secretsFile;
      # Managed enrollment is the only configuration that starts warp-svc.
      managed = cfg.enable && enrolling;
      # Gate the sops-install-secrets.service dependency on
      # sops.useSystemdActivation: the unit only exists in that mode (issue #37);
      # activation-script hosts decrypt before any unit ordering, so this is [].
      installSecretsDeps = sopsInstallSecretsDeps config;

      mdmTemplate = config.sops.templates."cloudflare-warp-mdm".path;

      # Linux mdm.xml is a bare <dict> plist fragment (no XML declaration, no
      # <plist> wrapper). Secret values are injected through sops placeholders so
      # the rendered file never enters the Nix store.
      mdmContent = ''
        <dict>
          <key>organization</key>
          <string>${config.sops.placeholder."cloudflare-warp/organization"}</string>
          <key>auth_client_id</key>
          <string>${config.sops.placeholder."cloudflare-warp/auth_client_id"}</string>
          <key>auth_client_secret</key>
          <string>${config.sops.placeholder."cloudflare-warp/auth_client_secret"}</string>
          <key>service_mode</key>
          <string>${cfg.serviceMode}</string>
          <key>auto_connect</key>
          <integer>${toString cfg.autoConnect}</integer>
          <key>switch_locked</key>
          ${if cfg.switchLocked then "<true/>" else "<false/>"}
        </dict>
      '';

      connectScript = ''
        managed_org=""
        registration_state="unknown"
        connected=""
        connect_requested=""
        unverified=0
        status=""
        attempt=0
        deadline=$((SECONDS + 120))

        if managed_org="$(cat ${
          config.sops.secrets."cloudflare-warp/organization".path
        } 2>/dev/null)" && [ -n "$managed_org" ]; then
          managed_org="''${managed_org//[[:space:]]/}"
        else
          managed_org=""
          echo "<3>cloudflare-warp-connect: managed organization secret unavailable; cannot verify registration"
        fi

        # registration_state is tri-state: confirmed (the daemon reported the
        # managed team), mismatch (it reported another team or none, which is
        # what an unmanaged/consumer registration returns), unknown (the check
        # itself did not answer). Only a mismatch is evidence of an unmanaged
        # tunnel; a timed-out or failed check must not tear a tunnel down.
        refresh_registration() {
          if [ -z "$managed_org" ]; then
            registration_state="unknown"
            return
          fi
          # Command substitution captures stdout alone, so the exact comparison
          # below cannot see a banner; leave stderr unredirected and let warp-cli
          # name the failure in the journal next to the exit code.
          registration=""
          registration_status=0
          registration="$(timeout 5s warp-cli --accept-tos registration organization)" ||
            registration_status=$?
          if [ "$registration_status" -ne 0 ]; then
            registration_state="unknown"
            echo "<3>cloudflare-warp-connect: registration check failed (exit $registration_status)"
            return
          fi
          registration="''${registration//[[:space:]]/}"
          if [ "$registration" = "$managed_org" ]; then
            registration_state="confirmed"
            echo "cloudflare-warp-connect: managed Zero Trust registration confirmed"
          else
            registration_state="mismatch"
            echo "<3>cloudflare-warp-connect: managed Zero Trust registration unavailable"
          fi
        }

        refresh_status() {
          if status="$(timeout 5s warp-cli status 2>&1)"; then
            status="''${status:-status unavailable}"
          else
            echo "cloudflare-warp-connect: status command failed: ''${status:-no response}"
            status="''${status:-status unavailable}"
          fi
          echo "cloudflare-warp-connect: $status"
          case "$status" in
            *Disconnected* | *"status unavailable"*) ;;
            *Connected*)
              case "$registration_state" in
                confirmed)
                  connected=1
                  ;;
                mismatch)
                  echo "<3>cloudflare-warp-connect: connected without managed Zero Trust registration; disconnecting"
                  if disconnect_output="$(timeout 5s warp-cli disconnect 2>&1)"; then
                    echo "cloudflare-warp-connect: disconnected unmanaged tunnel"
                  else
                    echo "<3>cloudflare-warp-connect: failed to disconnect unmanaged tunnel: ''${disconnect_output:-no response}"
                  fi
                  ;;
                *)
                  echo "<4>cloudflare-warp-connect: connected while the managed registration could not be verified; leaving the tunnel up"
                  unverified=$((unverified + 1))
                  ;;
              esac
              ;;
          esac
        }

        # managed_org is read once above, so an empty value keeps the connect gate
        # shut for every attempt. Exit instead of polling a decision that cannot
        # change before the deadline.
        if [ -z "$managed_org" ]; then
          echo "<3>cloudflare-warp-connect: managed organization secret unavailable; not connecting"
          exit 0
        fi

        # The daemon IPC socket and mdm.xml registration can settle at different
        # times, so poll both during the bounded readiness window. Two terminal
        # states end the run: a verified managed tunnel, and a live tunnel whose
        # registration went unanswered three times, where nothing is left to
        # request and the tunnel stays up.
        while [ -z "$connected" ] && [ "$unverified" -lt 3 ] && [ "$attempt" -lt 30 ] && [ "$SECONDS" -lt "$deadline" ]; do
          attempt=$((attempt + 1))
          refresh_registration
          refresh_status
          if [ -n "$connected" ] || [ "$unverified" -ge 3 ]; then
            break
          fi
          if [ "$registration_state" = "confirmed" ]; then
            if request_output="$(timeout 5s warp-cli --accept-tos connect 2>&1)"; then
              connect_requested=1
              echo "cloudflare-warp-connect: connect requested"
            else
              echo "cloudflare-warp-connect: connect request failed: ''${request_output:-no response}"
            fi
          else
            echo "<3>cloudflare-warp-connect: managed enrollment is not ready; not connecting"
          fi
          sleep 1
        done
        # Best-effort: name the state that ended the run and exit 0 so a user who
        # legitimately keeps WARP off does not leave the unit failed.
        if [ -z "$connected" ]; then
          if [ "$unverified" -gt 0 ]; then
            echo "<4>cloudflare-warp-connect: tunnel is up but its registration went unverified in $attempt attempts; left it connected"
          elif [ "$registration_state" = "mismatch" ]; then
            echo "<3>cloudflare-warp-connect: daemon is registered outside the managed organization after $attempt attempts"
          elif [ -n "$connect_requested" ]; then
            echo "<3>cloudflare-warp-connect: tunnel is not connected after $attempt attempts"
          else
            echo "<3>cloudflare-warp-connect: connect never succeeded (daemon unreachable or registration incomplete)"
          fi
        fi
      '';
    in
    {
      options.programs.cloudflare-warp.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Whether to install the WARP client. warp-svc and Zero Trust
            enrollment activate only when secrets/cloudflare-warp.yaml exists.
          '';
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.cloudflare-warp.override { headless = true; };
          defaultText = lib.literalExpression "pkgs.cloudflare-warp.override { headless = true; }";
          description = ''
            Cloudflare WARP package. Defaults to the headless build, which ships
            warp-cli, warp-svc, warp-dex, and warp-diag and omits the GUI taskbar.
          '';
        };

        serviceMode = lib.mkOption {
          type = lib.types.enum [
            "warp"
            "tunnelonly"
            "1dot1"
            "proxy"
            "postureonly"
          ];
          default = "warp";
          description = ''
            mdm.xml service_mode. "warp" is Full / Gateway with WARP (full tunnel
            plus Gateway DNS/HTTP filtering).
          '';
        };

        autoConnect = lib.mkOption {
          type = lib.types.ints.between 0 1440;
          default = 0;
          description = ''
            mdm.xml auto_connect: minutes before the client reconnects after a manual
            disconnect. 0 keeps it off until the user reconnects.
          '';
        };

        switchLocked = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "mdm.xml switch_locked; when true the user cannot disconnect WARP.";
        };

        connectOnBoot = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Run a best-effort oneshot `warp-cli connect` after the daemon starts.";
        };

        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Open the WARP UDP port in the firewall.";
        };

        udpPort = lib.mkOption {
          type = lib.types.port;
          default = 2408;
          description = "WARP UDP port to open when openFirewall is true.";
        };
      };

      config = lib.mkMerge [
        # Remove the wrapper-owned managed file whenever this host is not running
        # managed WARP. mdm.xml is authoritative for service_mode and caches the
        # service token, so a stale file would keep warp-svc in managed mode.
        # Leave an independently configured upstream service's state untouched.
        (lib.mkIf (!managed && !config.services.cloudflare-warp.enable) {
          systemd.tmpfiles.rules = [ "r ${rootDir}/mdm.xml" ];
        })

        # No managed credentials: ship the CLI (warp-cli, warp-diag) without the
        # privileged daemon.
        (lib.mkIf (cfg.enable && !enrolling) {
          environment.systemPackages = [ cfg.package ];

          warnings = [
            ''
              programs.cloudflare-warp.extended: secrets/cloudflare-warp.yaml is missing, so warp-svc
              is NOT started and only warp-cli is installed. Create the sops secret (see
              docs/cloudflare/warp/deployment.md) and rebuild to enroll.
            ''
          ];
        })

        (lib.mkIf managed (
          lib.mkMerge [
            {
              services.cloudflare-warp = {
                enable = true;
                inherit (cfg) package udpPort openFirewall;
              };

              warnings =
                lib.optional
                  (
                    (config.services.dnscrypt-proxy.enable || config.networking.networkmanager.dns == "dnsmasq")
                    && builtins.elem cfg.serviceMode [
                      "warp"
                      "1dot1"
                    ]
                  )
                  ''
                    programs.cloudflare-warp.extended.serviceMode "${cfg.serviceMode}" takes over DNS,
                    but a local resolver is bound to 127.0.0.1:53 (dnscrypt-proxy or NetworkManager
                    dnsmasq). Use serviceMode "tunnelonly"/"proxy" or disable the local resolver.
                  ''
                ++
                  lib.optional
                    (
                      config.networking.firewall.enable
                      && builtins.elem config.networking.firewall.checkReversePath [
                        true
                        "strict"
                      ]
                    )
                    ''
                      programs.cloudflare-warp.extended is enabled but
                      networking.firewall.checkReversePath is strict; the CloudflareWARP
                      interface routes asymmetrically, so return traffic is dropped. Import
                      the hosts-common vpn-defaults baseline (shareCommon = true) or set
                      networking.firewall.checkReversePath = "loose" on this host.
                    '';

              sops = {
                secrets = {
                  "cloudflare-warp/organization" = {
                    sopsFile = secretsFile;
                    key = "organization";
                    mode = "0400";
                  };
                  "cloudflare-warp/auth_client_id" = {
                    sopsFile = secretsFile;
                    key = "auth_client_id";
                    mode = "0400";
                  };
                  "cloudflare-warp/auth_client_secret" = {
                    sopsFile = secretsFile;
                    key = "auth_client_secret";
                    mode = "0400";
                  };
                };
                templates."cloudflare-warp-mdm" = {
                  content = mdmContent;
                  mode = "0600";
                  # Sole restart owner for this unit: sops compares the rendered
                  # template between generations, so both a rotated service token
                  # and a changed service_mode/auto_connect/switch_locked land
                  # here. A second restartTriggers hash on the unit would restart
                  # warp-svc twice for one activation under
                  # sops.useSystemdActivation.
                  restartUnits = [ "cloudflare-warp.service" ];
                };
              };

              # Install the rendered mdm.xml into rootDir right before warp-svc starts.
              # rootDir already exists from the upstream tmpfiles rule, and the sops
              # template is rendered during activation (before multi-user.target).
              systemd.services.cloudflare-warp = {
                # Order warp-svc after sops installs the secret/template so the
                # ExecStartPre install of mdm.xml sees the rendered file. No-op on
                # activation-script hosts (installSecretsDeps = []).
                after = installSecretsDeps;
                requires = installSecretsDeps;
                serviceConfig.ExecStartPre = [
                  # Credentials are substituted after evaluation, so no Nix-side
                  # quoting can escape them. An XML metacharacter in one would
                  # otherwise leave warp-svc reading a truncated mdm.xml and
                  # falling back to unmanaged mode; refuse to start instead.
                  "${pkgs.libxml2.bin}/bin/xmllint --noout ${mdmTemplate}"
                  "${pkgs.coreutils}/bin/install -D -m0600 -o root -g root ${mdmTemplate} ${rootDir}/mdm.xml"
                ];
              };
            }

            (lib.mkIf cfg.connectOnBoot {
              # Upholds restarts the oneshot whenever warp-svc is active and the
              # oneshot is not. Restart=always respawns warp-svc without an
              # explicit restart job, which BindsTo alone would only propagate as
              # a stop, leaving the host untunneled until the next rebuild.
              systemd.services.cloudflare-warp.upholds = [ "cloudflare-warp-connect.service" ];

              systemd.services.cloudflare-warp-connect = {
                description = "Cloudflare WARP connect on boot";
                after = [ "cloudflare-warp.service" ];
                bindsTo = [ "cloudflare-warp.service" ];
                wantedBy = [ "multi-user.target" ];
                # This script fails closed around a registration check, so hold it
                # to shellcheck plus errexit/nounset/pipefail.
                enableStrictShellChecks = true;
                path = [
                  pkgs.coreutils
                  cfg.package
                ];
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                  # The script bounds each IPC call and its retry window; this larger
                  # unit timeout covers the status queries and shell overhead.
                  TimeoutStartSec = 180;
                };
                script = connectScript;
              };
            })
          ]
        ))
      ];
    };
in
{
  nixpkgs.allowedUnfreePackages = [
    "cloudflare-warp"
    "cloudflare-warp-headless"
  ];

  flake.nixosModules.apps.cloudflare-warp = CloudflareWarpModule;
}
