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
    enable: Run warp-svc plus managed Zero Trust enrollment.
    organization: Zero Trust team name (the <team> in <team>.cloudflareaccess.com); null disables managed enrollment.
    serviceMode: mdm.xml service_mode (warp | tunnelonly | 1dot1 | proxy | postureonly).
    autoConnect: mdm.xml auto_connect minutes (0-1440); 0 keeps the client off after a manual disconnect.
    switchLocked: mdm.xml switch_locked; when true the user cannot disconnect.
    connectOnBoot: run a best-effort oneshot `warp-cli connect` after the daemon starts.

  Notes:
    * service_mode is authoritative via mdm.xml; the module never calls `warp-cli mode`.
    * Secrets (auth_client_id/auth_client_secret) live in secrets/cloudflare-warp.yaml (sops).
    * Sets networking.firewall.checkReversePath = "loose" (mkDefault); the WARP interface trips strict rp_filter.
    * Pairs with per-host enablement in modules/tpnix/cloudflare-warp.nix and modules/system76/cloudflare-warp.nix.
*/
_:
let
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
      secretsFile = "${secretsRoot}/cloudflare-warp.yaml";
      haveSecrets = builtins.pathExists secretsFile;
      enrolling = cfg.organization != null && haveSecrets;

      # Linux mdm.xml is a bare <dict> plist fragment (no XML declaration, no
      # <plist> wrapper). Secret values are injected through sops placeholders so
      # the rendered file never enters the Nix store.
      mdmContent = ''
        <dict>
          <key>organization</key>
          <string>${cfg.organization}</string>
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
    in
    {
      options.programs.cloudflare-warp.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to run warp-svc and enroll into Cloudflare Zero Trust.";
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

        organization = lib.mkOption {
          # Zero Trust team names are [A-Za-z0-9-]+. Constraining the type makes a
          # bad value (placeholder, whitespace, XML metacharacters) fail at eval
          # instead of rendering an unparsable mdm.xml that warp-svc rejects at
          # startup. cfg.organization is interpolated raw into the plist body.
          type = lib.types.nullOr (lib.types.strMatching "[A-Za-z0-9-]+");
          default = null;
          example = "my-team";
          description = ''
            Cloudflare Zero Trust team name (the <team> in <team>.cloudflareaccess.com).
            When null, the module runs warp-svc without managed enrollment.
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

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            services.cloudflare-warp = {
              enable = true;
              inherit (cfg) package udpPort openFirewall;
            };

            # WARP's CloudflareWARP interface trips strict reverse-path filtering.
            # mkDefault so a host firewall module can still override it.
            networking.firewall.checkReversePath = lib.mkDefault "loose";

            warnings =
              lib.optional
                (
                  config.services.dnscrypt-proxy.enable
                  && builtins.elem cfg.serviceMode [
                    "warp"
                    "1dot1"
                  ]
                )
                ''
                  programs.cloudflare-warp.extended.serviceMode "${cfg.serviceMode}" takes over DNS,
                  but services.dnscrypt-proxy is enabled (binds 127.0.0.1:53). Use serviceMode
                  "tunnelonly"/"proxy" or disable dnscrypt-proxy.
                ''
              ++ lib.optional (cfg.organization != null && !haveSecrets) ''
                programs.cloudflare-warp.extended: ${secretsFile} is missing; running warp-svc
                WITHOUT managed enrollment. Create the sops secret (see
                docs/cloudflare/warp/deployment.md) and rebuild.
              '';
          }

          (lib.mkIf enrolling {
            sops = {
              secrets."cloudflare-warp/auth_client_id" = {
                sopsFile = secretsFile;
                key = "auth_client_id";
                mode = "0400";
              };
              secrets."cloudflare-warp/auth_client_secret" = {
                sopsFile = secretsFile;
                key = "auth_client_secret";
                mode = "0400";
              };
              templates."cloudflare-warp-mdm" = {
                content = mdmContent;
                mode = "0600";
              };
            };

            # Install the rendered mdm.xml into rootDir right before warp-svc starts.
            # rootDir already exists from the upstream tmpfiles rule, and the sops
            # template is rendered during activation (before multi-user.target).
            systemd.services.cloudflare-warp = {
              serviceConfig.ExecStartPre = [
                "${pkgs.coreutils}/bin/install -D -m0600 -o root -g root ${
                  config.sops.templates."cloudflare-warp-mdm".path
                } ${rootDir}/mdm.xml"
              ];
              # Re-apply managed config when any non-secret mdm field changes.
              restartTriggers = [
                (builtins.toJSON {
                  inherit (cfg)
                    organization
                    serviceMode
                    autoConnect
                    switchLocked
                    ;
                })
              ];
            };
          })

          (lib.mkIf cfg.connectOnBoot {
            systemd.services.cloudflare-warp-connect = {
              description = "Cloudflare WARP connect on boot";
              after = [ "cloudflare-warp.service" ];
              requires = [ "cloudflare-warp.service" ];
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
              script = ''
                # Wait for the warp-svc IPC socket to answer before connecting.
                for _ in $(seq 1 30); do
                  if ${cfg.package}/bin/warp-cli status >/dev/null 2>&1; then
                    break
                  fi
                  sleep 1
                done

                # Managed enrollment (mdm.xml service token) registers the device and
                # accepts ToS, so no interactive `warp-cli registration new` is needed.
                # This connect is best-effort: log the outcome and exit 0 so a user who
                # legitimately keeps WARP off does not leave the unit failed.
                if ${cfg.package}/bin/warp-cli connect; then
                  echo "cloudflare-warp-connect: connect requested"
                else
                  echo "cloudflare-warp-connect: connect returned non-zero (already connected or daemon still settling)"
                fi
                ${cfg.package}/bin/warp-cli status || echo "cloudflare-warp-connect: status unavailable"
              '';
            };
          })
        ]
      );
    };
in
{
  nixpkgs.allowedUnfreePackages = [
    "cloudflare-warp"
    "cloudflare-warp-headless"
  ];

  flake.nixosModules.apps.cloudflare-warp = CloudflareWarpModule;
}
