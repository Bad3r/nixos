/*
  Package: rustdesk
  Description: Remote desktop client and host, run here against a self-hosted ID and relay server.
  Homepage: https://rustdesk.com
  Documentation: https://rustdesk.com/docs/en/
  Repository: https://github.com/rustdesk/rustdesk

  Summary:
    * Shares the live X11 session and the login screen with clipboard, audio, and file transfer, encoding through ffmpeg's hardware codecs.
    * Registers with the fleet's own ID server (hbbs) and relays every session through its relay (hbbr), both reachable over Cloudflare Mesh only.

  Options:
    --service: Root service that starts a server process for the active seat session, the login greeter included.
    --get-id: Print the ID other devices connect to.
    --password <password>: Set the permanent password from a root shell; the GUI keeps it out of argv.
    --option <key> [value]: Read or set one setting in the running service.

  Notes:
    * Package is rustdesk-flutter, the build with the hwcodec feature; the rustdesk attribute is the Sciter UI without it.
    * RustDesk has no system-wide config. rustdesk.service writes the managed [options] into root's RustDesk2.toml
      at every start, and as each user into the owner's and the greeter's, because the first server process to run
      pushes its own file back to root.
    * The registry host that sets rustdeskServer runs hbbs and hbbr with the key pair in secrets/rustdesk.yaml.
    * IPAddressAllow confines the client service, its server processes, hbbs, and hbbr to loopback and the CGNAT
      block that holds the Mesh.
*/
{ config, ... }:
let
  hostsRegistry = config.flake.lib.nixos.hosts or { };
  inherit (config.flake.lib.security) sopsInstallSecretsDeps;
  meshInterface = config.flake.lib.nixos._firewallMeshInterface;
  meshHostNames =
    config.flake.lib.nixos._cloudflareWarpMeshHostNames
      or (throw "modules/apps/cloudflare-warp.nix no longer exports flake.lib.nixos._cloudflareWarpMeshHostNames");
  warpSecretName =
    config.flake.lib.nixos._cloudflareWarpSecretName
      or (throw "modules/apps/cloudflare-warp.nix no longer exports flake.lib.nixos._cloudflareWarpSecretName");
  serverHosts = builtins.filter (name: hostsRegistry.${name}.rustdeskServer or false) (
    builtins.attrNames hostsRegistry
  );

  # Pinned in every RustDesk2.toml at service start, next to the server address,
  # key, and Mesh allocation that sops supplies.
  managedOptions = {
    # is_public() treats any URL ending in rustdesk.com as the public API and then
    # skips the heartbeat, sysinfo, and audit posts that a custom ID server would
    # otherwise draw in plaintext to its port 21114.
    "api-server" = "http://127.0.0.1:9/rustdesk.com";
    # Direct IP sessions skip the key exchange and run unencrypted.
    "direct-server" = "N";
    "enable-lan-discovery" = "N";
    "verification-method" = "use-permanent-password";
    "approve-mode" = "password";
    "enable-tunnel" = "N";
    "enable-terminal" = "N";
    "enable-camera" = "N";
    "allow-scope-violation-close" = "Y";
    # The GUI's stop toggle sets this, and the service then disables its own unit at every start.
    "stop-service" = "N";
  };
  # GUI settings, read from the user's own RustDesk_local.toml and never synced.
  managedLocalOptions = {
    "enable-check-update" = "N";
    "disable-discovery-panel" = "Y";
  };

  # Loopback carries hbbs's self-test; 100.64.0.0/10 holds every Mesh address.
  meshOnly = {
    IPAddressDeny = "any";
    IPAddressAllow = [
      "localhost"
      "100.64.0.0/10"
    ];
  };

  RustdeskModule =
    {
      config,
      lib,
      pkgs,
      hostName,
      metaOwner,
      secretsRoot,
      ...
    }:
    let
      cfg = config.programs.rustdesk.extended;
      hostFlags = hostsRegistry.${hostName} or { };
      secretFile = secretsRoot + "/rustdesk.yaml";
      secretExists = builtins.pathExists secretFile;
      sopsReady = hostFlags.sopsRuntimeReady or false;
      warpEnrolled = config.programs.cloudflare-warp.extended.enrolled;
      serverHost = if builtins.length serverHosts == 1 then builtins.head serverHosts else null;
      ready =
        secretExists
        && sopsReady
        && warpEnrolled
        && serverHost != null
        && builtins.elem serverHost meshHostNames;
      clientActive = cfg.enable && ready;
      serverActive = hostName == serverHost && ready;

      installSecretsDeps = sopsInstallSecretsDeps config;
      placeholder = name: config.sops.placeholder.${name};
      publicKeySecret = "rustdesk/server-public-key";
      secretKeySecret = "rustdesk/server-secret-key";
      serverAddressSecret = warpSecretName "mesh-host-${serverHost}";
      optionsTemplate = "rustdesk/options.json";
      hbbsEnvTemplate = "rustdesk/hbbs.env";
      hbbrEnvTemplate = "rustdesk/hbbr.env";

      owner = config.users.users.${metaOwner.username};
      greeter = config.users.users.lightdm;

      tomlPython = pkgs.python3.withPackages (ps: [ ps.tomlkit ]);
      mergeOptions = pkgs.writeText "rustdesk-merge-options.py" ''
        import json
        import os
        import sys
        import tomllib
        from pathlib import Path

        import tomlkit

        path = Path(sys.argv[1])
        managed = json.load(sys.stdin)
        try:
            raw = path.read_text(encoding="utf-8")
        except FileNotFoundError:
            raw = ""
        config = tomllib.loads(raw) if raw.strip() else {}
        options = config.setdefault("options", {})
        if any(options.get(key) != value for key, value in managed.items()):
            options.update(managed)
            path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            tmp = path.with_name(f".{path.name}.seed")
            fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as out:
                out.write(tomlkit.dumps(config))
            os.replace(tmp, path)
      '';

      # Each user's files are written by that user, so a link planted in a home
      # directory cannot redirect a root write.
      seedOptions = pkgs.writeShellApplication {
        name = "rustdesk-seed-options";
        runtimeInputs = [ pkgs.util-linux ];
        text = ''
          options=${config.sops.templates.${optionsTemplate}.path}
          local_options=${pkgs.writeText "rustdesk-local-options.json" (builtins.toJSON managedLocalOptions)}

          merge() {
            ${tomlPython}/bin/python3 -I ${mergeOptions} "$1"
          }

          # <user> <group> <file> <json>
          merge_as() {
            setpriv --reuid="$1" --regid="$2" --init-groups -- \
              ${tomlPython}/bin/python3 -I ${mergeOptions} "$3" <"$4"
          }

          merge /root/.config/rustdesk/RustDesk2.toml <"$options"
          merge_as ${owner.name} ${owner.group} ${owner.home}/.config/rustdesk/RustDesk2.toml "$options"
          merge_as ${owner.name} ${owner.group} ${owner.home}/.config/rustdesk/RustDesk_local.toml "$local_options"
          ${lib.optionalString config.services.xserver.displayManager.lightdm.enable ''
            merge_as ${greeter.name} ${greeter.group} ${greeter.home}/.config/rustdesk/RustDesk2.toml "$options"
          ''}
        '';
      };

      notReadyReason =
        if !secretExists then
          "${toString secretFile} is missing"
        else if !sopsReady then
          "flake.lib.nixos.hosts.${hostName}.sopsRuntimeReady is false"
        else if !warpEnrolled then
          "Cloudflare WARP is not enrolled here, and RustDesk runs over Mesh only"
        else if serverHost == null then
          "exactly one flake.lib.nixos.hosts entry must set rustdeskServer, and ${toString (builtins.length serverHosts)} do"
        else
          "${serverHost} has no Mesh address (cloudflareWarpMeshAddressReady)";
    in
    {
      options.programs.rustdesk.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Whether to run the RustDesk client and host service against the fleet's
            own ID and relay server. Nothing is installed until the host is enrolled
            in Cloudflare WARP and secrets/rustdesk.yaml decrypts, since an
            unconfigured client falls back to RustDesk's public servers.
          '';
        };

        package = lib.mkPackageOption pkgs "rustdesk-flutter" { };
      };

      config = lib.mkMerge [
        (lib.mkIf (clientActive || serverActive) {
          sops.secrets.${publicKeySecret} = {
            sopsFile = secretFile;
            format = "yaml";
            key = "server_public_key";
          };
        })

        (lib.mkIf clientActive {
          environment.systemPackages = [ cfg.package ];

          sops.templates.${optionsTemplate} = {
            content = builtins.toJSON (
              managedOptions
              // {
                "custom-rendezvous-server" = placeholder serverAddressSecret;
                "relay-server" = placeholder serverAddressSecret;
                key = placeholder publicKeySecret;
                whitelist = placeholder (warpSecretName "mesh-cidr");
              }
            );
            restartUnits = [ "rustdesk.service" ];
          };

          systemd.services.rustdesk = {
            description = "RustDesk remote desktop service";
            wantedBy = [ "multi-user.target" ];
            wants = [ "network-online.target" ];
            after = [
              "network-online.target"
              "systemd-user-sessions.service"
            ]
            ++ installSecretsDeps;
            requires = installSecretsDeps;
            # Run by bare name from the service and from the server process it
            # starts through sudo, which keeps this PATH.
            path = [
              "/run/wrappers"
              pkgs.gawk
              pkgs.getent
              pkgs.procps
              pkgs.which
              pkgs.xdg-utils
              pkgs.xrandr
            ];
            environment = {
              PULSE_LATENCY_MSEC = "60";
              PIPEWIRE_LATENCY = "1024/48000";
            };
            serviceConfig = meshOnly // {
              ExecStartPre = lib.getExe seedOptions;
              ExecStart = "${lib.getExe cfg.package} --service";
              # The server processes sit in this cgroup; mixed stops them after the service.
              KillMode = "mixed";
              TimeoutStopSec = 30;
              LimitNOFILE = 100000;
              Restart = "on-failure";
            };
          };
        })

        (lib.mkIf serverActive {
          services.rustdesk-server = {
            enable = true;
            # Used only for a peer that pins no relay of its own. The env file
            # supplies the address, so it stays out of the store.
            signal.relayHosts = [ "\${RELAY_SERVER}" ];
          };

          sops = {
            secrets.${secretKeySecret} = {
              sopsFile = secretFile;
              format = "yaml";
              key = "server_secret_key";
            };
            # A 64-byte KEY makes hbbs sign peer keys and admit only clients that
            # present the derived public key, without a key file on disk.
            templates.${hbbsEnvTemplate} = {
              content = ''
                KEY=${placeholder secretKeySecret}
                RELAY_SERVER=${placeholder serverAddressSecret}
              '';
              restartUnits = [ "rustdesk-signal.service" ];
            };
            templates.${hbbrEnvTemplate} = {
              content = ''
                KEY=${placeholder publicKeySecret}
              '';
              restartUnits = [ "rustdesk-relay.service" ];
            };
          };

          systemd.services = {
            rustdesk-signal = {
              after = installSecretsDeps;
              requires = installSecretsDeps;
              # Every session goes through hbbr here instead of a punched path.
              environment.ALWAYS_USE_RELAY = "Y";
              serviceConfig = meshOnly // {
                EnvironmentFile = config.sops.templates.${hbbsEnvTemplate}.path;
              };
            };
            rustdesk-relay = {
              after = installSecretsDeps;
              requires = installSecretsDeps;
              serviceConfig = meshOnly // {
                EnvironmentFile = config.sops.templates.${hbbrEnvTemplate}.path;
              };
            };
          };

          # 21115 serves the NAT test and online status, 21116 registration and
          # session setup, 21117 the relay. The web-client ports stay closed.
          networking.firewall.interfaces.${meshInterface} = {
            allowedTCPPorts = [
              21115
              21116
              21117
            ];
            allowedUDPPorts = [ 21116 ];
          };
        })

        (lib.mkIf ((cfg.enable || hostName == serverHost) && !ready) {
          warnings = [ "RustDesk is off on ${hostName} because ${notReadyReason}." ];
        })
      ];
    };
in
{
  flake.nixosModules.apps.rustdesk = RustdeskModule;
}
