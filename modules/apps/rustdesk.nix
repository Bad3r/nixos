/*
  Package: rustdesk
  Description: Remote desktop client and host, run here against a self-hosted ID and relay server.
  Homepage: https://rustdesk.com
  Documentation: https://rustdesk.com/docs/en/
  Repository: https://github.com/rustdesk/rustdesk

  Summary:
    * Shares the live X11 session and the login screen with clipboard, audio, and file transfer, encoding through ffmpeg's hardware codecs.
    * Registers with the fleet's own ID server (hbbs) and connects peers directly over Cloudflare Mesh, falling back to its relay (hbbr).

  Options:
    --service: Root service that starts a server process for the active seat session, the login greeter included.
    --get-id: Print the ID other devices connect to.
    --option <key> [value]: Read or set one setting in the running service.

  Notes:
    * Package is rustdesk-flutter, the build with the hwcodec feature; the rustdesk attribute is the Sciter UI without it.
    * RustDesk has no system-wide config. rustdesk.service writes the managed settings into root's files at every
      start, and as each user into the owner's and the greeter's, because the first server process to run pushes
      its own files back to root.
    * The ID, salt, and permanent password derive from secrets/rustdesk.yaml, so every host knows every other
      host's login and the owner's peer list carries it.
    * The registry host that sets rustdeskServer runs hbbs and hbbr with the key pair in secrets/rustdesk.yaml.
    * IPAddressAllow confines the client service, its server processes, hbbs, and hbbr to loopback and the CGNAT
      block that holds the Mesh. A GUI started from the user's session sits outside that cgroup, so only its
      settings keep its traffic on Mesh.
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
  # NixOS Mesh hosts, which the hosts-common baseline gives this client; the iPhone only controls.
  clientHosts = builtins.filter (name: hostsRegistry.${name}.shareCommon or false) meshHostNames;

  # Pinned in every RustDesk2.toml at service start, next to the server address,
  # key, and Mesh allocation that sops supplies.
  managedOptions = {
    # is_public() takes this for RustDesk's own API (1.5.0 by host, 1.4.9 by suffix)
    # and skips the heartbeat, sysinfo, and audit posts a custom server would draw,
    # with their fallback through hbbs. The name does not resolve.
    "api-server" = "http://off.rustdesk.com:9/rustdesk.com";
    # Direct IP sessions skip the key exchange and run unencrypted.
    "direct-server" = "N";
    "enable-lan-discovery" = "N";
    "verification-method" = "use-permanent-password";
    "approve-mode" = "password";
    "enable-tunnel" = "N";
    "enable-terminal" = "N";
    "enable-camera" = "N";
    # A rebooted host waits at its LUKS passphrase prompt, out of every session's reach.
    "enable-remote-restart" = "N";
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
      passwordSecret = "rustdesk/password";
      serverAddressSecret = warpSecretName "mesh-host-${serverHost}";
      optionsTemplate = "rustdesk/options.json";
      hbbsEnvTemplate = "rustdesk/hbbs.env";
      hbbrEnvTemplate = "rustdesk/hbbr.env";

      owner = config.users.users.${metaOwner.username};
      greeter = config.users.users.lightdm;

      seedPython = pkgs.python3.withPackages (ps: [
        ps.pynacl
        ps.tomlkit
      ]);
      # Mirrors hbb_common in rustdesk-flutter 1.5.0: symmetric_crypt and its "00"
      # framing in password_security.rs, the "01" storage in config/permanent_password.rs.
      seedHelper = pkgs.writeText "rustdesk-seed.py" ''
        import base64
        import functools
        import hashlib
        import hmac
        import json
        import os
        import sys
        import tomllib
        from pathlib import Path

        import nacl.exceptions
        import nacl.secret
        import nacl.utils
        import tomlkit

        NONCE = nacl.secret.SecretBox.NONCE_SIZE
        MAC = nacl.secret.SecretBox.MACBYTES


        @functools.cache
        def machine_box():
            # machine_uid::get(), which hbb_common::get_uuid() pads to the key size.
            for path in ("/var/lib/dbus/machine-id", "/etc/machine-id"):
                try:
                    uid = Path(path).read_text(encoding="utf-8").strip().encode()
                except OSError:
                    continue
                return nacl.secret.SecretBox(uid[:32].ljust(32, b"\0"))
            sys.exit("rustdesk-seed: no machine id")


        def b64decode(data):
            try:
                return base64.b64decode(data, validate=True)
            except ValueError:
                return None


        def seal(data):
            nonce = nacl.utils.random(NONCE)
            return b"\x01" + nonce + machine_box().encrypt(data, nonce).ciphertext


        def unseal(data):
            box = machine_box()
            if data[:1] == b"\x01" and len(data) >= 1 + NONCE + MAC:
                try:
                    return box.decrypt(data[1 + NONCE :], data[1 : 1 + NONCE])
                except nacl.exceptions.CryptoError:
                    pass
            try:
                return box.decrypt(data, bytes(NONCE))
            except nacl.exceptions.CryptoError:
                return None


        def seal_text(version, data):
            return version + base64.b64encode(seal(data)).decode()


        def open_text(value, version):
            if not isinstance(value, str) or not value.startswith(version):
                return None
            data = b64decode(value[len(version) :])
            return None if data is None else unseal(data)


        def stored_h1(value):
            inner = open_text(value, "01")
            if inner is None or not inner.startswith(b"00"):
                return None
            return b64decode(inner[2:])


        def peer_h1(value):
            raw = bytes(value) if isinstance(value, list) else b""
            if raw.startswith(b"00"):
                data = b64decode(raw[2:])
                plain = None if data is None else unseal(data)
                if plain is not None:
                    return plain
            return raw


        def apply_options(config, managed):
            options = config.setdefault("options", {})
            if all(options.get(key) == value for key, value in managed.items()):
                return False
            options.update(managed)
            return True


        def apply_identity(config, login):
            h1 = base64.b64decode(login["h1"])
            changed = False
            if open_text(config.get("enc_id"), "00") != login["id"].encode():
                config["enc_id"] = seal_text("00", login["id"].encode())
                config.pop("id", None)
                # As ipc::get_id() does on an ID change, so hbbs registers the key anew.
                config["key_confirmed"] = False
                config.pop("keys_confirmed", None)
                changed = True
            if config.get("salt") != login["salt"] or stored_h1(config.get("password")) != h1:
                config["salt"] = login["salt"]
                config["password"] = seal_text("01", b"00" + base64.b64encode(h1))
                changed = True
            return changed


        def apply_peer(config, login):
            h1 = base64.b64decode(login["h1"])
            changed = False
            if peer_h1(config.get("password")) != h1:
                config["password"] = list(b"00" + base64.b64encode(seal(h1)))
                changed = True
            # PeerConfig::batch_peers deletes a peer file whose info.platform is empty.
            if "info" not in config:
                config["info"] = login["info"]
                changed = True
            # The card title; a rename in the GUI stays.
            options = config.setdefault("options", {})
            if not options.get("alias"):
                options["alias"] = login["info"]["hostname"]
                changed = True
            return changed


        def apply_favorites(config, ids):
            favorites = config.setdefault("fav", [])
            missing = [rid for rid in ids if rid not in favorites]
            favorites.extend(missing)
            return bool(missing)


        def plan(password_file, key_file, me, owner, *hosts):
            password = Path(password_file).read_bytes()
            key = Path(key_file).read_bytes()
            if not password or not key:
                sys.exit("rustdesk-seed: empty password or server key")

            def login(host):
                def derive(label):
                    message = f"rustdesk-{label}:{host}".encode()
                    return hmac.new(key, message, hashlib.sha256).digest()

                rid = 100_000_000 + int.from_bytes(derive("id")[:8], "big") % 900_000_000
                salt = derive("salt").hex()[:32]
                h1 = hashlib.sha256(password + salt.encode()).digest()
                return {"id": str(rid), "salt": salt, "h1": base64.b64encode(h1).decode()}

            logins = {host: login(host) for host in hosts}
            if len({entry["id"] for entry in logins.values()}) != len(logins):
                sys.exit("rustdesk-seed: two hosts derive the same ID")
            info = {"username": owner, "platform": "Linux"}
            peers = [
                logins[host] | {"info": info | {"hostname": host}} for host in hosts if host != me
            ]
            json.dump({"self": logins[me], "peers": peers}, sys.stdout)


        def write_toml(path, config):
            path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            tmp = path.with_name(f".{path.name}.seed")
            fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as out:
                out.write(tomlkit.dumps(config))
            os.replace(tmp, path)


        def main(mode, *args):
            if mode == "plan":
                plan(*args)
                return
            apply = {
                "options": apply_options,
                "identity": apply_identity,
                "peer": apply_peer,
                "favorites": apply_favorites,
            }[mode]
            path = Path(args[0])
            try:
                raw = path.read_text(encoding="utf-8")
            except FileNotFoundError:
                raw = ""
            config = tomllib.loads(raw) if raw.strip() else {}
            if apply(config, json.load(sys.stdin)):
                write_toml(path, config)


        main(*sys.argv[1:])
      '';

      # Each user's files are written by that user, so a link planted in a home
      # directory cannot redirect a root write.
      seedConfig = pkgs.writeShellApplication {
        name = "rustdesk-seed-config";
        runtimeInputs = [
          pkgs.jq
          pkgs.util-linux
        ];
        text = ''
          options=${config.sops.templates.${optionsTemplate}.path}
          local_options=${pkgs.writeText "rustdesk-local-options.json" (builtins.toJSON managedLocalOptions)}

          seed() {
            ${seedPython}/bin/python3 -I ${seedHelper} "$@"
          }

          # <user> <group> <mode> <file>, the managed values on stdin
          seed_as() {
            setpriv --reuid="$1" --regid="$2" --init-groups -- \
              ${seedPython}/bin/python3 -I ${seedHelper} "''${@:3}"
          }

          plan=$(seed plan ${config.sops.secrets.${passwordSecret}.path} \
            ${config.sops.secrets.${publicKeySecret}.path} \
            ${hostName} ${owner.name} ${lib.escapeShellArgs (lib.unique ([ hostName ] ++ clientHosts))})
          login=$(jq -c .self <<<"$plan")

          seed options /root/.config/rustdesk/RustDesk2.toml <"$options"
          seed identity /root/.config/rustdesk/RustDesk.toml <<<"$login"
          seed_as ${owner.name} ${owner.group} options ${owner.home}/.config/rustdesk/RustDesk2.toml <"$options"
          seed_as ${owner.name} ${owner.group} options ${owner.home}/.config/rustdesk/RustDesk_local.toml <"$local_options"
          seed_as ${owner.name} ${owner.group} identity ${owner.home}/.config/rustdesk/RustDesk.toml <<<"$login"
          jq -c '.peers[]' <<<"$plan" | while read -r peer; do
            seed_as ${owner.name} ${owner.group} peer \
              "${owner.home}/.config/rustdesk/peers/$(jq -r .id <<<"$peer").toml" <<<"$peer"
          done
          jq -c '[.peers[].id]' <<<"$plan" |
            seed_as ${owner.name} ${owner.group} favorites ${owner.home}/.config/rustdesk/RustDesk_local.toml
          ${lib.optionalString config.services.xserver.displayManager.lightdm.enable ''
            seed_as ${greeter.name} ${greeter.group} options ${greeter.home}/.config/rustdesk/RustDesk2.toml <"$options"
            seed_as ${greeter.name} ${greeter.group} identity ${greeter.home}/.config/rustdesk/RustDesk.toml <<<"$login"
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

          sops.secrets.${passwordSecret} = {
            sopsFile = secretFile;
            format = "yaml";
            key = "password";
            restartUnits = [ "rustdesk.service" ];
          };

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
              ExecStartPre = lib.getExe seedConfig;
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
