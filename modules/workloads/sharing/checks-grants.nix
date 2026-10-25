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
          *) echo '{"error": {"code": "not-found", "message": "no sandbox"}}'; exit 1 ;;
        esac
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
              systemd.tmpfiles.rules = [ "f /srv/www/index.html 0644 root root - granted" ];

              workloads = {
                networks = {
                  sbx = {
                    id = 2;
                    egress = "none";
                    isolatePeers = true;
                    libvirt.sessionAttach = true;
                  };
                  # The open host port is the positive control for the bridges.
                  desktop = {
                    id = 1;
                    egress = "none";
                    hostPorts.tcp = [ 7500 ];
                  };
                };

                # A declared guest without libvirt: the namespace holds its address.
                sharing.endpoints.guest.dev = {
                  trust = "trusted";
                  interfaces = [
                    {
                      network = "desktop";
                      address = "172.16.1.10";
                    }
                  ];
                  ports = [ 8080 ];
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
            };
          };

        testScript = ''
          import json
          import shlex

          machine.wait_for_unit("workload-grants.service")
          machine.wait_for_unit("workload-grantd.socket")

          for bridge, gateway in (("vn-sbx", "172.16.2.1"), ("vn-desktop", "172.16.1.1")):
              machine.succeed(f"ip link add {bridge} type bridge && ip addr add {gateway}/24 dev {bridge} && ip link set {bridge} up")
          for ns, bridge, address, gateway in (
              ("sb", "vn-sbx", "172.16.2.50", "172.16.2.1"),
              ("peer", "vn-sbx", "172.16.2.51", "172.16.2.1"),
              ("dev", "vn-desktop", "172.16.1.10", "172.16.1.1"),
          ):
              machine.succeed(
                  f"ip netns add {ns}",
                  f"ip link add w-{ns} type veth peer name eth0 netns {ns}",
                  f"ip link set w-{ns} master {bridge} up",
                  f"ip -n {ns} addr add {address}/24 dev eth0",
                  f"ip -n {ns} link set eth0 up && ip -n {ns} link set lo up",
                  f"ip -n {ns} route add default via {gateway}",
              )

          python = "${pkgs.python3.interpreter}"

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

          with subtest("revoke deletes the element and its connections"):
              machine.succeed(
                  f"systemd-run --unit=hold ip netns exec sb {python} -c"
                  " \"import socket, time; s = socket.create_connection(('172.16.2.1', 8000)); time.sleep(300)\""
              )
              marked = "conntrack -L -f ipv4 -s 172.16.2.50 -d 172.16.2.1 -p tcp --dport 8000 -m 0x00100000/0x00f00000"
              machine.wait_until_succeeds(f"{marked} | grep -F ESTABLISHED")
              status, answer = workloads("revoke", dev_8000)
              assert status == 0 and answer == {"revoked": [dev_8000]}, answer
              machine.fail(f"{marked} | grep -F ESTABLISHED")
              opened -= {"sb-dev-8000"}
              expect(opened)

          with subtest("revoke --all takes one source and its routes"):
              status, answer = workloads("revoke", "--all", "sbx-probe")
              assert status == 0 and answer == {"revoked": sorted([api, guest])}, answer
              assert routes() == [], routes()
              expect({"control", "dev-8100"})
              assert live() == {dev_8100: "host:dev:8100"}

          with subtest("a grant expires with its TTL"):
              grant("sbx-probe", "host:dev:8001", "--ttl", "5s")
              machine.succeed("ip netns exec sb curl -sf -m 3 http://172.16.2.1:8001/")
              machine.wait_until_fails("ip netns exec sb curl -sf --connect-timeout 1 -m 3 http://172.16.2.1:8001/", timeout=30)
              assert live() == {dev_8100: "host:dev:8100"}

          with subtest("the journal records caller and decision"):
              entries = [
                  json.loads(line)
                  for line in machine.succeed("journalctl -t workload-grant -o json").splitlines()
              ]
              granted = [entry for entry in entries if entry.get("WORKLOAD_GRANT_DECISION") == "granted"]
              assert len(granted) == 5 and all(entry["WORKLOAD_GRANT_CALLER_UID"] == "1000" for entry in granted), granted
              assert any("workloads" in entry["WORKLOAD_GRANT_CALLER_CMDLINE"] for entry in granted), granted
              assert any(entry.get("WORKLOAD_GRANT_ERROR") == "max-concurrent" for entry in entries)

          with subtest("a reload restores a deleted table"):
              machine.succeed("nft delete table inet workload_grants")
              machine.succeed("systemctl reload nftables.service")
              # The propagated reload is its own job, queued after nftables' own.
              machine.wait_until_succeeds("nft list chain inet workload_grants input | grep -F @grants")
              assert live() == {}
        '';
      };
    };
}
