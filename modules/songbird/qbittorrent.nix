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
  # Proton VPN WireGuard profile "songbird-protonvpn" on server SA#3, generated
  # with NAT-PMP port forwarding on. Proton hands every profile 10.2.0.2/32
  # and answers DNS at 10.2.0.1 inside the tunnel.
  proton = {
    address = "10.2.0.2/32";
    dns = "10.2.0.1";
    endpoint = "79.135.105.132:51820";
    publicKey = "ef+2TRMxo9EYXN1a01zrRfoxyx6uPKTHiFOmWi+6Uzw=";
  };
  # Same number inside the namespace (qBittorrent) and on the host loopback
  # (the proxy socket); the desktop client's Web UI already answered here.
  webuiPort = 8080;
  webuiUrl = "http://127.0.0.1:${toString webuiPort}";
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
      downloadDir = "${config.users.users.${metaOwner.username}.home}/Downloads";
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
            # own; the units below bind the same file explicitly.
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

            services.qbittorrent = {
              enable = true;
              # Downloads stay the owner's files, as under the desktop client.
              user = metaOwner.username;
              group = "users";
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
                    # Loopback inside the namespace: only the proxy reaches
                    # it, and every proxied request arrives from 127.0.0.1, so
                    # the localhost bypass stands in for the password the
                    # handler and the renewal unit would otherwise need.
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

                qbittorrent = {
                  requires = [ netnsUnit ];
                  wants = [ "wireguard-${tunnel}.target" ];
                  after = [
                    netnsUnit
                    "wireguard-${tunnel}.target"
                  ];
                  partOf = [ netnsUnit ];
                  serviceConfig = {
                    NetworkNamespacePath = netnsPath;
                    # The upstream address-family list has no AF_UNIX, so
                    # nss-resolve cannot reach systemd-resolved and lookups fall
                    # through to the dns module reading this file; blocking the
                    # varlink socket keeps that true if the list ever grows.
                    BindReadOnlyPaths = [ "${resolvConf}:/etc/resolv.conf" ];
                    InaccessiblePaths = [ "-/run/systemd/resolve/io.systemd.Resolve" ];
                    # Upstream hides /home entirely; the tmpfs form admits a bind
                    # of the save path alone.
                    ProtectHome = lib.mkForce "tmpfs";
                    BindPaths = [ downloadDir ];
                  };
                };

                # Proton assigns a port per tunnel session and expires the mapping
                # after 60 s, so both protocols are renewed every 45 s and the port
                # is pushed into the running session when it changes.
                qbittorrent-port-forward = {
                  description = "Proton VPN NAT-PMP port renewal for qBittorrent";
                  bindsTo = [ "qbittorrent.service" ];
                  after = [ "qbittorrent.service" ];
                  wantedBy = [ "qbittorrent.service" ];
                  path = [
                    pkgs.coreutils
                    pkgs.curl
                    pkgs.gnused
                    pkgs.libnatpmp
                  ];
                  serviceConfig = {
                    Restart = "always";
                    RestartSec = 10;
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
                          if curl -fsS -o /dev/null --data-urlencode "json={\"listen_port\":$udp}" \
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
                  requires = [ "qbittorrent.service" ];
                  after = [ "qbittorrent.service" ];
                  serviceConfig = {
                    ExecStart = "${config.systemd.package}/lib/systemd/systemd-socket-proxyd 127.0.0.1:${toString webuiPort}";
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
                };
              };

              # The socket listens on the host loopback; the proxy it activates
              # joins the namespace and connects to the Web UI there.
              sockets.qbittorrent-webui = {
                description = "qBittorrent Web UI proxy socket";
                wantedBy = [ "sockets.target" ];
                socketConfig.ListenStream = "127.0.0.1:${toString webuiPort}";
              };
            };
          }
        ]
        ++ lib.optionals (!secretsReady) [
          {
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

      # The desktop handler replaces the Qt client, which apps-enable.nix turns
      # off here, as the magnet and .torrent target.
      host.defaults.torrentClient = "qbittorrent-webui";
      programs."qbittorrent-webui".extended.url = webuiUrl;
    };
}
