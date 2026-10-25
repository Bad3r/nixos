# NixOS VM test for runtime grants: namespaces on two workload bridges stand in
# for a sandbox, its peer, and a declared guest. CI only forces its drvPath; run
# it with
#   nix build "path:.#checks.x86_64-linux.workloads-grants"
{
  config,
  metaOwner,
  nixosAppHelpers,
  ...
}:
let
  inherit (config.flake) nixosModules;
  inherit (nixosAppHelpers) getApp;
  owner = metaOwner.username;
in
{
  perSystem =
    { pkgs, ... }:
    let
      # Stands in for `sbx info`, which needs a session libvirt.
      fakeSbx = pkgs.writeShellScriptBin "sbx" ''
        case "$1 $2" in
          "info probe") echo '{"name": "probe", "domain": "sbx-probe", "address": "172.16.2.50"}' ;;
          "info peer") echo '{"name": "peer", "domain": "sbx-peer", "address": "172.16.2.51"}' ;;
          "info offline") echo '{"name": "offline", "domain": "sbx-offline", "address": null}' ;;
          "info stale") echo '{"name": "stale", "domain": "sbx-stale", "address": "172.16.2.52"}' ;;
          *) echo '{"error": {"code": "not-found", "message": "no sandbox"}}'; exit 1 ;;
        esac
      '';

      # Each logs one line per round trip or received datagram, so a stalled flow stops its log.
      flows = pkgs.writeText "flows.py" ''
        import os
        import socket
        import socketserver
        import sys
        import threading
        import time

        role, host, port = sys.argv[1], sys.argv[2], int(sys.argv[3])

        class Echo(socketserver.StreamRequestHandler):
            def handle(self):
                for line in self.rfile:
                    self.wfile.write(line)

        if role == "echo-server":
            socketserver.ThreadingTCPServer.allow_reuse_address = True
            socketserver.ThreadingTCPServer((host, port), Echo).serve_forever()
        elif role == "udp-echo-server":
            server = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            server.bind((host, port))
            while True:
                data, peer = server.recvfrom(64)
                server.sendto(data, peer)
        elif role == "push-server":
            server = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            server.bind((host, port))
            _, peer = server.recvfrom(64)
            while True:
                server.sendto(b"p", peer)
                time.sleep(0.2)
        else:
            log = open(sys.argv[4], "a", buffering=1)
            # Sending ends hold off while this file exists.
            pause = sys.argv[4].removesuffix(".log") + ".pause"
            if role.startswith("stream-"):
                # Either end sends unprompted and logs what it reads.
                if role == "stream-server":
                    stream, _ = socket.create_server((host, port)).accept()
                else:
                    stream = socket.create_connection((host, port), timeout=2)
                    stream.settimeout(None)

                def send():
                    while True:
                        if not os.path.exists(pause):
                            stream.sendall(b"x\n")
                        time.sleep(0.2)

                threading.Thread(target=send, daemon=True).start()
                for _ in stream.makefile("rb"):
                    log.write("ok\n")
                sys.exit()
            if role == "udp-sink":
                sink = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                sink.bind((host, port))
                while True:
                    sink.recv(64)
                    log.write("leak\n")
            if role == "udp-pinger":
                # Keeps sending whether or not echoes come back.
                pinger = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                pinger.settimeout(0.5)
                while True:
                    if os.path.exists(pause):
                        time.sleep(0.2)
                        continue
                    pinger.sendto(b"x", (host, port))
                    try:
                        pinger.recv(64)
                        log.write("ok\n")
                    except TimeoutError:
                        pass
                    time.sleep(0.2)
            if role == "echo-client":
                stream = socket.create_connection((host, port), timeout=2).makefile("rwb")
                while True:
                    stream.write(b"x\n")
                    stream.flush()
                    assert stream.readline() == b"x\n"
                    log.write("ok\n")
                    time.sleep(0.2)
            client = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            client.sendto(b"hi", (host, port))
            while True:
                client.recv(64)
                log.write("ok\n")
      '';
    in
    {
      checks.workloads-grants = pkgs.testers.runNixOSTest {
        name = "workloads-grants";

        nodes.machine =
          { lib, pkgs, ... }:
          {
            imports = [
              nixosModules."workloads-networks"
              nixosModules."workloads-vms"
              nixosModules."workloads-sharing"
              (getApp "libvirt")
              (getApp "workloads")
            ];

            options.programs.cloudflare-warp.extended.enable = lib.mkEnableOption "the WARP row";

            config = {
              _module.args = {
                hostName = "machine";
                inherit metaOwner;
              };

              users.users = {
                ${owner} = {
                  isNormalUser = true;
                  uid = 1000;
                };
                eve.isNormalUser = true;
              };

              networking.nftables.enable = true;
              programs.workloads.extended.package = pkgs.callPackage ../../../packages/workloads { };
              environment.systemPackages = [
                fakeSbx
                pkgs.conntrack-tools
              ];
              networking.dhcpcd.denyInterfaces = [
                "vn-*"
                "w-*"
              ];
              systemd.tmpfiles.rules = [
                "f /srv/www/index.html 0644 root root - granted"
                "f /srv/leak/index.html 0644 root root - leaked"
                "d /run/flows 0755 root root -"
              ];

              workloads = {
                networks = {
                  sbx = {
                    id = 2;
                    egress = "none";
                    isolatePeers = true;
                    libvirt = {
                      sessionAttach = true;
                      bindLeases = true;
                    };
                  };
                  # The open host port is the positive control for the bridges.
                  desktop = {
                    id = 1;
                    egress = "none";
                    hostPorts.tcp = [
                      7500
                      7501
                    ];
                  };
                };

                # A declared guest without libvirt: the namespace holds its address.
                sharing.endpoints.guest.dev = {
                  trust = "trusted";
                  interfaces = [
                    {
                      network = "desktop";
                      address = "172.16.1.10";
                      mac = "52:54:00:00:01:10";
                    }
                  ];
                  ports = [
                    8080
                    {
                      port = 8082;
                      proto = "udp";
                    }
                    {
                      port = 8083;
                      proto = "udp";
                    }
                  ];
                };

                host.services = {
                  api = {
                    ports = [ 7000 ];
                    bind = "loopback";
                    grantable = true;
                  };
                  dev = {
                    ports = [
                      {
                        from = 8000;
                        to = 8999;
                      }
                      {
                        from = 8000;
                        to = 8999;
                        proto = "udp";
                      }
                    ];
                    bind = "any";
                    grantable = true;
                  };
                  closed = {
                    ports = [ 9000 ];
                    bind = "any";
                  };
                };

                grants = {
                  maxConcurrent = 3;
                  allow = [
                    {
                      from = [ "sbx-*" ];
                      to = [
                        "host:api"
                        "host:dev"
                        "guest:dev:8080"
                        "guest:dev:8082/udp"
                        "guest:dev:8083/udp"
                      ];
                    }
                    {
                      from = [ "guest:dev" ];
                      to = [ "host:dev:8100" ];
                      maxTtl = "24h";
                    }
                  ];
                };
              };

              specialisation.nohelper.configuration.workloads.grants.allow = lib.mkForce [ ];
            };
          };

        testScript = ''
          import json
          import shlex

          machine.wait_for_unit("workload-grants.service")
          machine.wait_for_unit("workload-grantd.socket")

          for bridge, gateway in (("vn-sbx", "172.16.2.1"), ("vn-desktop", "172.16.1.1")):
              machine.succeed(f"ip link add {bridge} type bridge && ip addr add {gateway}/24 dev {bridge} && ip link set {bridge} up")
          for ns, bridge, address, gateway, mac in (
              ("sb", "vn-sbx", "172.16.2.50", "172.16.2.1", "52:54:00:00:02:50"),
              ("peer", "vn-sbx", "172.16.2.51", "172.16.2.1", "52:54:00:00:02:51"),
              ("dev", "vn-desktop", "172.16.1.10", "172.16.1.1", "52:54:00:00:01:10"),
          ):
              machine.succeed(
                  f"ip netns add {ns}",
                  f"ip link add w-{ns} type veth peer name eth0 netns {ns}",
                  f"ip link set w-{ns} master {bridge} up",
                  f"ip -n {ns} link set eth0 address {mac}",
                  f"ip -n {ns} addr add {address}/24 dev eth0",
                  f"ip -n {ns} link set eth0 up && ip -n {ns} link set lo up",
                  f"ip -n {ns} route add default via {gateway}",
              )

          python = "${pkgs.python3.interpreter}"

          # libvirt's lease file for the bridge, as dnsmasq writes it; .52 holds none.
          expiry = int(machine.succeed("date +%s")) + 3600
          leases = [
              {"ip-address": "172.16.2.50", "mac-address": "52:54:00:00:02:50", "expiry-time": expiry},
              {"ip-address": "172.16.2.51", "mac-address": "52:54:00:00:02:51", "expiry-time": expiry},
          ]
          machine.succeed(
              "mkdir -p /var/lib/libvirt/dnsmasq",
              f"echo {shlex.quote(json.dumps(leases))} > /var/lib/libvirt/dnsmasq/vn-sbx.status",
          )

          def serve(name, port, bind, ns=None):
              prefix = f"ip netns exec {ns} " if ns else ""
              machine.succeed(
                  f"systemd-run --unit=listen-{name} {prefix}{python} -m http.server {port} --bind {bind} --directory /srv/www"
              )

          for port in (7500, 8000, 8001, 8100, 9000):
              serve(str(port), port, "0.0.0.0")
          serve("api", 7000, "127.0.0.1")
          serve("dev-8080", 8080, "172.16.1.10", "dev")
          serve("dev-8081", 8081, "172.16.1.10", "dev")
          serve("sb-8090", 8090, "172.16.2.50", "sb")
          for port in (7000, 7500, 8000, 8001, 8100, 9000):
              machine.wait_until_succeeds(f"curl -sf http://127.0.0.1:{port}/ | grep -Fx granted")
          machine.wait_until_succeeds("ip netns exec dev curl -sf http://172.16.1.10:8080/ | grep -Fx granted")
          machine.wait_until_succeeds("ip netns exec sb curl -sf http://172.16.2.50:8090/ | grep -Fx granted")

          paths = {
              "control": ("dev", "172.16.1.1:7500"),
              "sb-control": ("sb", "172.16.2.1:7500"),
              "sb-dev-8000": ("sb", "172.16.2.1:8000"),
              "sb-dev-8001": ("sb", "172.16.2.1:8001"),
              "sb-api": ("sb", "172.16.2.1:7000"),
              "sb-guest-8080": ("sb", "172.16.1.10:8080"),
              "sb-guest-8081": ("sb", "172.16.1.10:8081"),
              "sb-closed": ("sb", "172.16.2.1:9000"),
              "peer-dev-8000": ("peer", "172.16.2.1:8000"),
              "peer-api": ("peer", "172.16.2.1:7000"),
              "dev-8100": ("dev", "172.16.1.1:8100"),
              "dev-8000": ("dev", "172.16.1.1:8000"),
              "dev-to-sb": ("dev", "172.16.2.50:8090"),
          }

          def expect(opened):
              reached = {
                  name
                  for name, (ns, endpoint) in paths.items()
                  if machine.execute(f"ip netns exec {ns} curl -sf --connect-timeout 1 -m 3 http://{endpoint}/")[0] == 0
              }
              assert reached == set(opened), f"reached {sorted(reached)}, expected {sorted(opened)}"

          def workloads(*args, user="${owner}"):
              status, out = machine.execute(f"runuser -u {user} -- workloads --json {shlex.join(args)}")
              return status, json.loads(out)

          def grant(*args):
              status, answer = workloads("grant", *args)
              assert status == 0, answer
              return answer["grant"]["id"]

          def refused(code, *args):
              status, answer = workloads("grant", *args)
              assert status == 1 and answer["error"]["code"] == code, answer

          def live():
              status, answer = workloads("grants")
              assert status == 0, answer
              return {entry["id"]: entry["target"] for entry in answer["grants"]}

          def routes():
              return json.loads(machine.succeed("ip -j rule show pref 30900"))

          with subtest("nothing is granted by default"):
              expect({"control"})
              assert live() == {}

          with subtest("a grant opens exactly its path"):
              dev_8000 = grant("sbx-probe", "host:dev:8000", "--ttl", "10m")
              expect({"control", "sb-dev-8000"})

          with subtest("loopback services, guests, and guest sources take grants"):
              api = grant("sbx-probe", "host:api")
              guest = grant("sbx-probe", "guest:dev:8080")
              dev_8100 = grant("dev", "host:dev:8100", "--ttl", "12h")
              opened = {"control", "sb-dev-8000", "sb-api", "sb-guest-8080", "dev-8100"}
              expect(opened)
              assert live() == {dev_8000: "host:dev:8000", api: "host:api", guest: "guest:dev:8080", dev_8100: "host:dev:8100"}
              assert sorted((rule["iif"], rule["src"], rule["dst"]) for rule in routes()) == [
                  ("vn-desktop", "172.16.1.10", "172.16.2.50"),
                  ("vn-sbx", "172.16.2.50", "172.16.1.10"),
              ], routes()

          with subtest("the policy refuses what it does not name"):
              refused("max-concurrent", "sbx-probe", "host:dev:8001")
              refused("ttl", "sbx-peer", "host:dev:8000", "--ttl", "3h")
              refused("not-allowed", "sbx-peer", "guest:dev:8081")
              refused("not-allowed", "sbx-peer", "host:closed")
              refused("not-allowed", "dev", "host:api")
              refused("no-address", "sbx-offline", "host:dev")
              refused("no-lease", "sbx-stale", "host:dev")
              refused("invalid-target", "sbx-peer", "10.0.0.1:22")
              expect(opened)

          with subtest("only the owner reaches the helper"):
              assert machine.succeed("stat -c '%U %a' /run/workloads/grant.sock").strip() == "${owner} 600"
              status, answer = workloads("grants", user="eve")
              assert status == 1 and answer["error"]["code"] == "os-error", answer

          with subtest("grants survive a ruleset reload and restart"):
              machine.succeed("systemctl reload nftables.service")
              assert len(live()) == 4
              expect(opened)
              machine.succeed("systemctl restart nftables.service")
              machine.wait_for_unit("workload-grants.service")
              assert len(live()) == 4
              expect(opened)

          with subtest("revoke deletes the element"):
              status, answer = workloads("revoke", dev_8000)
              assert status == 0 and answer == {"revoked": [dev_8000]}, answer
              opened -= {"sb-dev-8000"}
              expect(opened)

          with subtest("revoke --all takes one source and its routes"):
              status, answer = workloads("revoke", "--all", "sbx-probe")
              assert status == 0 and answer == {"revoked": sorted([api, guest])}, answer
              assert routes() == [], routes()
              expect({"control", "dev-8100"})
              assert live() == {dev_8100: "host:dev:8100"}

          flows = "${flows}"

          def flow(name, ns, role, endpoint):
              host, port = endpoint.split(":")
              log = f" /run/flows/{name}.log" if role.endswith(("client", "pinger", "sink")) else ""
              machine.succeed(f"systemd-run --unit=flow-{name} ip netns exec {ns} {python} {flows} {role} {host} {port}{log}")

          def server(name, role, bind, port, ns="dev"):
              prefix = "" if ns is None else f"ip netns exec {ns} "
              machine.succeed(f"systemd-run --unit=flow-{name} {prefix}{python} {flows} {role} {bind} {port}")

          def count(name):
              return int(machine.succeed(f"cat /run/flows/{name}.log 2>/dev/null | wc -l"))

          def alive(name):
              before = count(name)
              machine.sleep(2)
              return count(name) > before

          def wait_stopped(names, timeout):
              for _ in range(timeout):
                  if not any(alive(name) for name in names):
                      return
              raise AssertionError(f"{[name for name in names if alive(name)]} still pass traffic")

          server("echo-8003", "echo-server", "0.0.0.0", 8003, None)
          server("echo-8005", "echo-server", "0.0.0.0", 8005, None)
          server("echo-8006", "echo-server", "0.0.0.0", 8006, None)
          server("echo-8011", "echo-server", "0.0.0.0", 8011, None)
          server("echo-8013", "echo-server", "0.0.0.0", 8013, None)
          server("udp-8083", "udp-echo-server", "172.16.1.10", 8083)
          server("push-8004", "push-server", "0.0.0.0", 8004, None)
          server("push-8082", "push-server", "172.16.1.10", 8082)
          machine.wait_until_succeeds("ss -ltn | grep -q ':8006 '")

          with subtest("expiry stops every connection of the grant in both directions"):
              expiring = grant("sbx-probe", "host:dev:8003", "--ttl", "25s")
              grant("sbx-probe", "host:dev:8004/udp", "--ttl", "25s")
              grant("sbx-probe", "guest:dev:8082/udp", "--ttl", "25s")
              # A TCP round trip to the host, UDP the host pushes back, and UDP a guest pushes back.
              flow("echo", "sb", "echo-client", "172.16.2.1:8003")
              flow("host-push", "sb", "push-client", "172.16.2.1:8004")
              flow("guest-push", "sb", "push-client", "172.16.1.10:8082")
              for name in ("echo", "host-push", "guest-push"):
                  machine.wait_until_succeeds(f"test $(wc -l < /run/flows/{name}.log) -gt 3", timeout=20)
                  assert alive(name), name
              wait_stopped(["echo", "host-push", "guest-push"], 20)
              assert live() == {dev_8100: "host:dev:8100"}
              status, answer = workloads("revoke", expiring)
              assert status == 1 and answer["error"]["code"] == "not-found", answer

          with subtest("revoke stops only that grant's connections"):
              first = grant("sbx-probe", "host:dev:8005")
              grant("sbx-probe", "host:dev:8006")
              flow("first", "sb", "echo-client", "172.16.2.1:8005")
              flow("second", "sb", "echo-client", "172.16.2.1:8006")
              for name in ("first", "second"):
                  machine.wait_until_succeeds(f"test $(wc -l < /run/flows/{name}.log) -gt 3", timeout=20)
              workloads("revoke", first)
              wait_stopped(["first"], 5)
              assert alive("second")
              workloads("revoke", "--all", "sbx-probe")
              wait_stopped(["second"], 5)

          def wait_expired(grant_id):
              for _ in range(60):
                  if grant_id not in live():
                      return
                  machine.sleep(1)
              raise AssertionError(f"{grant_id} outlived its TTL")

          with subtest("a later grant outlives an earlier one of the same source"):
              short = grant("sbx-probe", "host:dev:8010", "--ttl", "6s")
              grant("sbx-probe", "host:dev:8011", "--ttl", "40s")
              flow("longer", "sb", "echo-client", "172.16.2.1:8011")
              machine.wait_until_succeeds("test $(wc -l < /run/flows/longer.log) -gt 3", timeout=20)
              wait_expired(short)
              machine.sleep(2)
              assert alive("longer")
              workloads("revoke", "--all", "sbx-probe")
              wait_stopped(["longer"], 5)
              # Equal TTLs started apart: the second must not end with the first.
              first = grant("sbx-probe", "host:dev:8012", "--ttl", "20s")
              machine.sleep(8)
              grant("sbx-probe", "host:dev:8013", "--ttl", "20s")
              flow("equal", "sb", "echo-client", "172.16.2.1:8013")
              machine.wait_until_succeeds("test $(wc -l < /run/flows/equal.log) -gt 3", timeout=20)
              wait_expired(first)
              machine.sleep(2)
              assert alive("equal")
              flow("equal-new", "sb", "echo-client", "172.16.2.1:8013")
              machine.wait_until_succeeds("test $(wc -l < /run/flows/equal-new.log) -gt 3", timeout=10)
              workloads("revoke", "--all", "sbx-probe")

          with subtest("a grant follows the leased MAC, not the address"):
              moved = grant("sbx-probe", "host:dev:8000")
              expect({"control", "sb-dev-8000", "dev-8100"})
              machine.succeed("ip -n sb link set eth0 address 52:54:00:00:02:99", "ip neigh flush dev vn-sbx")
              expect({"control", "dev-8100"})
              machine.succeed("ip -n sb link set eth0 address 52:54:00:00:02:50", "ip neigh flush dev vn-sbx")
              expect({"control", "sb-dev-8000", "dev-8100"})
              workloads("revoke", moved)

          def two_way(name, ns, endpoint, server_ns=None):
              host, port = endpoint.split(":")
              bind = host if server_ns else "0.0.0.0"
              prefix = f"ip netns exec {server_ns} " if server_ns else ""
              machine.succeed(f"systemd-run --unit=flow-{name}-server {prefix}{python} {flows} stream-server {bind} {port} /run/flows/{name}-server.log")
              machine.wait_until_succeeds(f"{prefix}ss -ltn | grep -q ':{port} '")
              flow(name, ns, "stream-client", endpoint)
              for log in (name, f"{name}-server"):
                  machine.wait_until_succeeds(f"test $(wc -l < /run/flows/{log}.log) -gt 3", timeout=20)

          with subtest("revoke stops connections the target side keeps sending on"):
              pushed = grant("sbx-probe", "host:dev:8020")
              kept = grant("sbx-probe", "host:dev:8021")
              pushed_udp = grant("sbx-peer", "host:dev:8022/udp")
              forwarded = grant("sbx-probe", "guest:dev:8080")
              machine.succeed("systemctl stop listen-dev-8080")
              two_way("pushed", "sb", "172.16.2.1:8020")
              two_way("kept", "sb", "172.16.2.1:8021")
              two_way("forwarded", "sb", "172.16.1.10:8080", "dev")
              server("push-8022", "push-server", "0.0.0.0", 8022, None)
              flow("pushed-udp", "peer", "push-client", "172.16.2.1:8022")
              machine.wait_until_succeeds("test $(wc -l < /run/flows/pushed-udp.log) -gt 3", timeout=20)
              for grant_id in (pushed, pushed_udp, forwarded):
                  status, answer = workloads("revoke", grant_id)
                  assert status == 0 and answer == {"revoked": [grant_id]}, answer
              wait_stopped(["pushed", "pushed-server", "pushed-udp", "forwarded", "forwarded-server"], 5)
              assert alive("kept") and alive("kept-server")
              machine.succeed("systemctl restart workload-grants.service")
              machine.succeed("systemctl restart nftables.service")
              machine.wait_for_unit("workload-grants.service")
              assert not any(alive(name) for name in ("pushed", "pushed-server", "pushed-udp", "forwarded", "forwarded-server"))
              assert alive("kept") and alive("kept-server")
              workloads("revoke", kept)
              wait_stopped(["kept", "kept-server"], 5)
              machine.succeed("systemctl stop flow-forwarded-server")
              serve("dev-8080", 8080, "172.16.1.10", "dev")
              machine.wait_until_succeeds("ip netns exec dev curl -sf http://172.16.1.10:8080/ | grep -Fx granted")

          def stays_cut(names):
              before = {name: count(name) for name in names}
              machine.sleep(6)
              grown = [name for name in names if count(name) > before[name]]
              assert not grown, f"{grown} pass traffic again"

          # Short enough that an entry ends within a subtest.
          machine.succeed(
              "sysctl -w net.netfilter.nf_conntrack_tcp_timeout_close=2"
              " net.netfilter.nf_conntrack_udp_timeout=3 net.netfilter.nf_conntrack_udp_timeout_stream=3"
          )

          with subtest("a mid-stream segment opens no connection on a bridge"):
              two_way("loose", "dev", "172.16.1.1:7501")
              machine.succeed("conntrack -D -f ipv4 -p tcp --dport 7501")
              wait_stopped(["loose", "loose-server"], 5)

          with subtest("an ended grant stays cut after its entry closes"):
              # The sandbox ignores resets and retransmits until the reset entry times out.
              machine.succeed(
                  "ip netns exec sb nft add table inet deaf",
                  "ip netns exec sb nft 'add chain inet deaf input { type filter hook input priority 0; }'",
                  "ip netns exec sb nft add rule inet deaf input tcp flags rst drop",
              )
              silent = grant("sbx-probe", "host:dev:8030")
              two_way("silent", "sb", "172.16.2.1:8030")
              machine.succeed("touch /run/flows/silent-server.pause")
              machine.sleep(1)
              workloads("revoke", silent)
              machine.succeed("systemctl restart workload-grants.service", "systemctl restart nftables.service")
              machine.wait_for_unit("workload-grants.service")
              machine.sleep(8)
              machine.succeed("rm /run/flows/silent-server.pause")
              stays_cut(["silent", "silent-server"])
              machine.succeed("ip netns exec sb nft delete table inet deaf")

          with subtest("a later grant of the path admits only new connections"):
              first = grant("sbx-probe", "host:dev:8031")
              two_way("regrant", "sb", "172.16.2.1:8031")
              machine.succeed("touch /run/flows/regrant.pause /run/flows/regrant-server.pause")
              machine.sleep(1)
              workloads("revoke", first)
              grant("sbx-probe", "host:dev:8031")
              machine.succeed("rm /run/flows/regrant.pause /run/flows/regrant-server.pause")
              stays_cut(["regrant", "regrant-server"])
              two_way("regrant-new", "sb", "172.16.2.1:8031")
              workloads("revoke", "--all", "sbx-probe")

          with subtest("a sandbox's datagrams stay cut past the UDP timeout"):
              quiet = grant("sbx-probe", "host:dev:8032/udp")
              server("udp-8032", "udp-echo-server", "0.0.0.0", 8032, None)
              flow("quiet-udp", "sb", "udp-pinger", "172.16.2.1:8032")
              machine.wait_until_succeeds("test $(wc -l < /run/flows/quiet-udp.log) -gt 3", timeout=20)
              workloads("revoke", quiet)
              machine.succeed("touch /run/flows/quiet-udp.pause")
              machine.sleep(5)
              machine.succeed("rm /run/flows/quiet-udp.pause")
              stays_cut(["quiet-udp"])

          with subtest("a granted path never leaves through the uplink"):
              # A namespace behind the host's default route answers for the guest's address.
              machine.succeed(
                  "ip netns add lan",
                  "ip link add w-lan type veth peer name eth0 netns lan",
                  "ip addr add 192.168.77.1/24 dev w-lan && ip link set w-lan up",
                  "ip -n lan addr add 192.168.77.2/24 dev eth0 && ip -n lan addr add 172.16.1.10/32 dev lo",
                  "ip -n lan link set eth0 up && ip -n lan link set lo up",
                  "ip -n lan route add default via 192.168.77.1",
                  "ip route replace default via 192.168.77.2 dev w-lan",
                  f"systemd-run --unit=listen-lan ip netns exec lan {python} -m http.server 8080 --bind 172.16.1.10 --directory /srv/leak",
              )
              crossing = grant("sbx-probe", "guest:dev:8080")
              stream = grant("sbx-probe", "guest:dev:8083/udp")
              machine.succeed("ip netns exec sb curl -sf -m 3 http://172.16.1.10:8080/ | grep -Fx granted")
              # An established stream across the bridge, and a sink behind the uplink.
              machine.succeed("touch /run/flows/leak.log")
              flow("leak", "lan", "udp-sink", "172.16.1.10:8083")
              flow("stream", "sb", "udp-pinger", "172.16.1.10:8083")
              machine.wait_until_succeeds("test $(wc -l < /run/flows/stream.log) -gt 3", timeout=20)
              machine.succeed("ip link set vn-desktop down")
              machine.sleep(3)
              assert not alive("stream")
              assert count("leak") == 0, machine.succeed("cat /run/flows/leak.log | wc -l")
              machine.wait_until_succeeds("curl -sf -m 3 http://172.16.1.10:8080/ | grep -Fx leaked")
              machine.fail("ip netns exec sb curl -sf --connect-timeout 1 -m 3 http://172.16.1.10:8080/")
              machine.succeed("ip link set vn-desktop up")
              workloads("revoke", crossing)
              workloads("revoke", stream)

          with subtest("the journal records caller and decision"):
              entries = [
                  json.loads(line)
                  for line in machine.succeed("journalctl -t workload-grant -o json").splitlines()
              ]
              granted = [entry for entry in entries if entry.get("WORKLOAD_GRANT_DECISION") == "granted"]
              assert len(granted) >= 5 and all(entry["WORKLOAD_GRANT_CALLER_UID"] == "1000" for entry in granted), granted
              assert any("workloads" in entry["WORKLOAD_GRANT_CALLER_CMDLINE"] for entry in granted), granted
              assert any(entry.get("WORKLOAD_GRANT_ERROR") == "max-concurrent" for entry in entries)

          with subtest("a reload restores a deleted table"):
              machine.succeed("nft delete table inet workload_grants")
              machine.succeed("systemctl reload nftables.service")
              # The propagated reload is its own job, queued after nftables' own.
              machine.wait_until_succeeds("nft list chain inet workload_grants input | grep -F @grants")
              assert live() == {}

          with subtest("removing the grant table cuts every grant"):
              grant("sbx-probe", "host:dev:8033")
              two_way("held", "sb", "172.16.2.1:8033")
              machine.succeed("/run/current-system/specialisation/nohelper/bin/switch-to-configuration test")
              machine.fail("nft list table inet workload_grants")
              assert machine.succeed("conntrack -L -f ipv4 -m 0x00100000/0x00f00000 2>/dev/null | wc -l").strip() == "0"
              wait_stopped(["held", "held-server"], 5)
        '';
      };
    };
}
