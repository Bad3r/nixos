# qBittorrent runs as a service inside the `torrent` network namespace, whose
# only route is a Proton VPN WireGuard tunnel, so nothing it sends can leave
# through the host's routes, WARP's tunnel, or a dropped VPN. The tunnel's
# outer UDP packets are the only thing the host sees; the nixos-songbird WARP
# profile excludes the endpoint so they bypass the WARP tunnel at full speed
# (docs/cloudflare/warp/deployment.md, Change a profile's exclude list).
{
  config,
  secretsRoot,
  ...
}:
let
  secretFile = secretsRoot + "/protonvpn.yaml";
  secretExists = builtins.pathExists secretFile;
  # Both halves, as every other secret consumer here gates (services.nix).
  secretsReady = config.flake.lib.nixos.hosts.songbird.sopsRuntimeReady && secretExists;
  privateKeySecret = "protonvpn/wireguard-private-key";

  netns = "torrent";
  netnsUnit = "netns-${netns}.service";
  netnsPath = "/run/netns/${netns}";
  tunnel = "wg-torrent";
  tunnelUnit = "wireguard-${tunnel}.service";
  # nixpkgs' wireguard module names the peer unit after the interface and the
  # peer's own `name`; this is the unit that installs the default route, and
  # it needs the same restart propagation as the interface unit itself.
  tunnelPeerUnitName = "wireguard-${tunnel}-peer-proton";
  qbittorrentUnit = "qbittorrent.service";
  # Proton VPN WireGuard profile "songbird-protonvpn" on server SA#3, generated
  # with NAT-PMP port forwarding on. Proton hands every profile 10.2.0.2/32
  # and answers DNS at 10.2.0.1 inside the tunnel.
  proton = {
    address = "10.2.0.2/32";
    dns = "10.2.0.1";
    endpoint = "79.135.105.132:51820";
    publicKey = "ef+2TRMxo9EYXN1a01zrRfoxyx6uPKTHiFOmWi+6Uzw=";
  };
  # Also the proxy's host port: qBittorrent rejects a Host header naming another.
  webuiPort = 8989;
  webuiUrl = "http://127.0.0.1:${toString webuiPort}";
  inherit (config.flake.lib.nixos) _firewallLocalNetworkCidrs _firewallMeshInterface;
in
{
  configurations.nixos.songbird.module =
    {
      config,
      lib,
      pkgs,
      metaOwner,
      ...
    }:
    let
      resolvConf = pkgs.writeText "${netns}-resolv.conf" "nameserver ${proton.dns}\n";
      # An overlay, not a bind over /etc/resolv.conf: the kernel detaches a
      # bind whose file the host recreates, which warp-svc does on every DNS
      # change (docs/cloudflare/warp/troubleshooting.md) and activation on
      # every switch, after which the sandbox reads the host's 127.0.2.2
      # servers that nothing in the namespace answers.
      resolvConfext = pkgs.runCommandLocal "${netns}-resolv-confext" { } ''
        mkdir -p "$out/etc/extension-release.d"
        cp ${resolvConf} "$out/etc/resolv.conf"
        # systemd matches the release file name to the directory name.
        echo "ID=_any" > "$out/etc/extension-release.d/extension-release.$(basename "$out")"
      '';
      downloadDir = "${config.users.users.${metaOwner.username}.home}/Downloads";
      inherit (config.services.qbittorrent) profileDir;
      # Shared by every unit that runs inside the namespace as an unprivileged,
      # dynamically allocated user with no capabilities of its own.
      hardening = {
        NetworkNamespacePath = netnsPath;
        DynamicUser = true;
        CapabilityBoundingSet = "";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProcSubset = "pid";
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        RestrictAddressFamilies = [ "AF_INET" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" ];
      };
    in
    {
      imports =
        lib.optionals secretsReady [
          {
            sops.secrets.${privateKeySecret} = {
              sopsFile = secretFile;
              format = "yaml";
              key = "songbird/wireguard_private_key";
              owner = "root";
              group = "root";
              mode = "0400";
              restartUnits = [ "wireguard-${tunnel}.service" ];
            };

            # `ip netns exec torrent` binds this over /etc/resolv.conf on its
            # own; the service reads the same file through its overlay.
            environment.etc."netns/${netns}/resolv.conf".source = resolvConf;

            # The interface is created in the host namespace, which pins its
            # UDP socket to the host's routes, then moved into the namespace,
            # where the peer unit installs the default route over it.
            networking.wireguard.interfaces.${tunnel} = {
              interfaceNamespace = netns;
              privateKeyFile = config.sops.secrets.${privateKeySecret}.path;
              ips = [ proton.address ];
              peers = [
                {
                  name = "proton";
                  inherit (proton) publicKey endpoint;
                  # IPv4 only: ipv6.disable=1 (hosts/common/disable-ipv6.nix)
                  # leaves no AF_INET6 for the ::/0 route the profile lists.
                  allowedIPs = [ "0.0.0.0/0" ];
                  persistentKeepalive = 25;
                }
              ];
            };

            # Runs as the upstream `qbittorrent` system user (nologin shell,
            # locked password, no home): its only writable paths are the
            # profile and the save path below.
            services.qbittorrent = {
              enable = true;
              inherit webuiPort;
              # Installed over qBittorrent.conf on every start (nixpkgs module),
              # so a preference changed in the Web UI lasts until the next
              # restart unless it is declared here.
              serverConfig = {
                LegalNotice.Accepted = true;
                BitTorrent.Session = {
                  DefaultSavePath = downloadDir;
                  QueueingSystemEnabled = false;
                };
                Core.AutoDeleteAddedTorrentFile = "Never";
                # libtorrent's own NAT-PMP would race the renewal unit below
                # for the same Proton mapping.
                Network.PortForwardingEnabled = false;
                Preferences = {
                  General.Locale = "en";
                  WebUI = {
                    # Every proxied request arrives from 127.0.0.1.
                    Address = "127.0.0.1";
                    LocalHostAuth = false;
                  };
                };
              };
            };
            systemd = {
              services = {
                # Only lo comes up here. The namespace's single route arrives with
                # the tunnel interface, so a process inside has no other way out.
                "netns-${netns}" = {
                  description = "${netns} network namespace";
                  path = [ pkgs.iproute2 ];
                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                  };
                  script = ''
                    [ -e ${netnsPath} ] || ip netns add ${netns}
                    ip -n ${netns} link set lo up
                  '';
                  preStop = "ip netns delete ${netns}";
                };

                # The namespace unit owns the namespace, so the tunnel follows its
                # stops and restarts.
                "wireguard-${tunnel}" = {
                  requires = [ netnsUnit ];
                  after = [ netnsUnit ];
                  partOf = [ netnsUnit ];
                };

                # nixpkgs generates this unit from the `peers` entry above; it is
                # the one that installs the default route, and only `partOf` (not
                # the default `requires`/`after` on the interface unit) restarts
                # it together with the interface, so a namespace or key-rotation
                # restart cannot leave wg-torrent up with no route.
                "${tunnelPeerUnitName}" = {
                  partOf = [ tunnelUnit ];
                };

                qbittorrent = {
                  requires = [ netnsUnit ];
                  wants = [ "wireguard-${tunnel}.target" ];
                  after = [
                    netnsUnit
                    "wireguard-${tunnel}.target"
                  ];
                  # Also tied to the tunnel service itself: libtorrent pins
                  # listen sockets per device, so a key rotation that restarts
                  # wg-torrent (sops restartUnits) must restart qBittorrent too,
                  # not just follow the namespace.
                  partOf = [
                    netnsUnit
                    tunnelUnit
                  ];
                  serviceConfig = {
                    NetworkNamespacePath = netnsPath;
                    # The profile root: mode 0700 and UMask=0077 since resume
                    # data carries private tracker passkeys. systemd applies
                    # the mode on every start and chowns the tree recursively
                    # when the root's owner differs, which is how a profile
                    # written under another user (the desktop-era copy, an
                    # operator restore) becomes the service's without a step.
                    StateDirectory = lib.removePrefix "/var/lib/" profileDir;
                    StateDirectoryMode = "0700";
                    UMask = "0077";
                    # Nothing the service can write is executable: the save
                    # path, the profile, and the shared /tmp (upstream keeps
                    # PrivateTmp off) are noexec, and only the store runs.
                    NoExecPaths = [ "/" ];
                    ExecPaths = [ "/nix/store" ];
                    # The upstream address-family list has no AF_UNIX, so
                    # nss-resolve cannot reach systemd-resolved and lookups fall
                    # through to the dns module reading the overlay's
                    # resolv.conf; blocking the varlink socket keeps that true
                    # if the list ever grows.
                    ExtensionDirectories = [ "${resolvConfext}" ];
                    InaccessiblePaths = [ "-/run/systemd/resolve/io.systemd.Resolve" ];
                    # Upstream hides /home entirely; the tmpfs form admits a bind
                    # of the save path alone.
                    ProtectHome = lib.mkForce "tmpfs";
                    # Not `-`-prefixed: systemd.tmpfiles below must create this
                    # before the unit starts, since BindPaths refuses a missing
                    # source and ProtectHome=tmpfs leaves no way to create it
                    # from inside the unit.
                    BindPaths = [ downloadDir ];
                  };
                };

                # Proton assigns a port per tunnel session and expires the mapping
                # after 60 s, so both protocols are renewed every 45 s and the port
                # is pushed into the running session when it changes.
                qbittorrent-port-forward = {
                  description = "Proton VPN NAT-PMP port renewal for qBittorrent";
                  bindsTo = [ qbittorrentUnit ];
                  after = [ qbittorrentUnit ];
                  wantedBy = [ qbittorrentUnit ];
                  # bindsTo alone can miss a restart: systemd's job coalescing
                  # skips a BindsTo= peer's stop while the target has a pending
                  # restart job, which would leave this loop running with a
                  # `last` cached from before qBittorrent picked a new port.
                  partOf = [
                    netnsUnit
                    qbittorrentUnit
                  ];
                  path = [
                    pkgs.coreutils
                    pkgs.curl
                    pkgs.gnused
                    pkgs.libnatpmp
                  ];
                  serviceConfig = hardening // {
                    Restart = "always";
                    RestartSec = 10;
                  };
                  script = ''
                    mapped() {
                      natpmpc -a 1 0 "$1" 60 -g ${proton.dns} \
                        | sed -n 's/^Mapped public port \([0-9]*\) protocol .*/\1/p'
                    }
                    last=""
                    while :; do
                      udp=$(mapped udp)
                      tcp=$(mapped tcp)
                      if [ -n "$udp" ] && [ "$udp" = "$tcp" ]; then
                        if [ "$udp" != "$last" ]; then
                          # Bounded: a Web UI that accepted the TCP connection but
                          # never answers (stalled recheck, hung alert loop) must
                          # not block this loop past the next mapping's 60 s lease.
                          if curl -fsS -o /dev/null --max-time 10 \
                              --data-urlencode "json={\"listen_port\":$udp}" \
                              ${webuiUrl}/api/v2/app/setPreferences; then
                            echo "listen port set to $udp"
                            last=$udp
                          else
                            echo "could not set listen port $udp through the Web UI" >&2
                          fi
                        fi
                        sleep 45
                      else
                        echo "NAT-PMP mapping failed (udp '$udp', tcp '$tcp')" >&2
                        last=""
                        sleep 10
                      fi
                    done
                  '';
                };

                qbittorrent-webui = {
                  description = "qBittorrent Web UI proxy into the ${netns} namespace";
                  requires = [ qbittorrentUnit ];
                  after = [ qbittorrentUnit ];
                  # See qbittorrent-port-forward above: Requires= alone does not
                  # restart this unit when the namespace or qBittorrent itself
                  # restarts, which strands the proxy's setns() on a deleted
                  # namespace until it is restarted by hand.
                  partOf = [
                    netnsUnit
                    qbittorrentUnit
                  ];
                  # A tunnel or namespace flap can fail this unit's start faster
                  # than the default 5-in-10s burst while it retries; that must
                  # not permanently trip the socket into service-start-limit-hit.
                  startLimitIntervalSec = 0;
                  serviceConfig = hardening // {
                    # Idle timeout: this is a human-driven surface opened a few
                    # times a day, not a reason to hold the namespace open and a
                    # DynamicUser process resident for the machine's uptime.
                    ExecStart = "${config.systemd.package}/lib/systemd/systemd-socket-proxyd --exit-idle-time=10min 127.0.0.1:${toString webuiPort}";
                  };
                };
              };

              # tmpfiles, not `-`-prefixed BindPaths, owns creating the save
              # path: xdg-user-dirs only creates ~/Downloads at the owner's
              # first graphical login, which has no ordering against this unit.
              tmpfiles.settings."10-qbittorrent-save-path".${downloadDir}.d = {
                user = metaOwner.username;
                group = "users";
                mode = "0755";
              };

              # The service reaches the owner's tree through ACLs alone. The
              # default entries make any folder the owner creates a save path
              # at once and keep the owner in charge of what the service
              # writes; the recursive walk covers what predates them or came
              # in by mv. A file of its own, sorted after the one above: in
              # one file the attribute order would put `A+` ahead of `d`, and
              # tmpfiles skips an ACL on a path that does not exist yet.
              tmpfiles.settings."20-qbittorrent-save-path-acl".${downloadDir}."A+".argument =
                lib.concatMapStringsSep "," (user: "u:${user}:rwX,d:u:${user}:rwx")
                  [
                    config.services.qbittorrent.user
                    metaOwner.username
                  ];

              sockets.qbittorrent-webui = {
                description = "qBittorrent Web UI proxy socket";
                wantedBy = [ "sockets.target" ];
                socketConfig.ListenStream = "0.0.0.0:${toString webuiPort}";
              };
            };

            networking.firewall = {
              interfaces.${_firewallMeshInterface}.allowedTCPPorts = [ webuiPort ];
              extraCommands = lib.concatMapStrings (
                cidr: "iptables -A nixos-fw -s ${cidr} -p tcp --dport ${toString webuiPort} -j nixos-fw-accept\n"
              ) _firewallLocalNetworkCidrs;
            };

            # Inside the secretsReady arm: without it, nothing above creates the
            # namespace, the service, or the socket, and a torrentClient default
            # with no backend would leave every magnet click posting to a proxy
            # that was never built. The handler's enable rides along because
            # its url has no default and an enabled handler forces it.
            host.defaults.torrentClient = "qbittorrent-webui";
            programs."qbittorrent-webui".extended = {
              enable = lib.mkOverride 1000 true;
              url = webuiUrl;
            };
          }
        ]
        ++ lib.optionals (!secretsReady) [
          {
            # apps-enable.nix turns the Qt client off, so the common
            # torrentClient default would fail the default-apps assertion here.
            host.defaults.torrentClient = null;
            warnings = [
              (
                if secretExists then
                  "songbird qBittorrent service skipped because flake.lib.nixos.hosts.songbird.sopsRuntimeReady is false."
                else
                  "songbird qBittorrent service skipped because ${toString secretFile} is missing."
              )
            ];
          }
        ];
    };
}
