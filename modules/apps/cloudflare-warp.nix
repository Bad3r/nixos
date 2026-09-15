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

  Options:
    enable: Whether this host enrolls and runs warp-svc (the common baseline leaves it off).
    package: WARP package; the headless build ships warp-cli, warp-svc, warp-dex, and warp-diag.
    serviceMode: mdm.xml service_mode, `warp` (Gateway with WARP, WARP owns DNS) or `tunnelonly` (traffic only).
*/
{ config, ... }:
let
  hostsRegistry = config.flake.lib.nixos.hosts or { };
  inherit (config.flake.lib.security) sopsInstallSecretsDeps;
  meshInterface =
    config.flake.lib.nixos._firewallMeshInterface
      or (throw "modules/hosts/common/firewall.nix no longer exports flake.lib.nixos._firewallMeshInterface");

  CloudflareWarpModule =
    {
      config,
      lib,
      pkgs,
      hostName,
      secretsRoot,
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

      secretName = key: "cloudflare-warp/${key}";
      placeholder = key: config.sops.placeholder.${secretName key};
      templateName = "cloudflare-warp-mdm";
      installSecretsDeps = sopsInstallSecretsDeps config;
      tunnelDevice = "sys-subsystem-net-devices-${meshInterface}.device";
      resolvedDropIn = "/run/systemd/resolved.conf.d/cloudflare-warp.conf";
      resolvedRoute = pkgs.writeText "cloudflare-warp-resolved.conf" ''
        [Resolve]
        DNS=127.0.2.2 127.0.2.3
        Domains=~.
      '';
      # `all`, unlike `main`, exits 0 while resolved has no process to signal.
      reloadResolved = "${config.systemd.package}/bin/systemctl kill --kill-whom=all --signal=SIGHUP systemd-resolved.service";
    in
    {
      options.programs.cloudflare-warp.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enroll this host into Cloudflare Zero Trust with its service token and run warp-svc.";
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
        (lib.mkIf enrolled {
          services.cloudflare-warp = {
            enable = true;
            inherit (cfg) package;
            # The client only dials out (MASQUE over UDP 443); the upstream
            # default opens inbound UDP 2408 that nothing listens on.
            openFirewall = false;
          };

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
          };

          # A bare <dict> plist fragment: no XML declaration, no <plist>
          # wrapper. The values are hex strings and a DNS label, so nothing
          # needs escaping. auto_connect present, at 0, starts the client
          # Connected after install and reboot while a manual disconnect
          # holds until the next boot; onboarding false suppresses the
          # client's first-launch screens.
          sops.templates.${templateName} = {
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

          systemd.services.cloudflare-warp = {
            after = installSecretsDeps;
            requires = installSecretsDeps;
            # warp-svc opens mdm.xml with O_NOFOLLOW, so the tmpfs render is
            # bind-mounted in as a regular file instead of symlinked (ELOOP).
            serviceConfig.BindReadOnlyPaths = [
              "${config.sops.templates.${templateName}.path}:${config.services.cloudflare-warp.rootDir}/mdm.xml"
            ];
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
                reloadResolved
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
                "Cloudflare WARP enrollment is disabled on ${hostName} because it has no flake.lib.nixos.hosts entry; add one in modules/${hostName}/policy.nix."
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

  flake.nixosModules.apps.cloudflare-warp = CloudflareWarpModule;
}
