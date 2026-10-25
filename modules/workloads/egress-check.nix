# NixOS VM test for workload egress enforcement. CI only forces its drvPath;
# run it with
#   nix build "path:.#checks.x86_64-linux.workloads-egress"
{ config, ... }:
let
  inherit (config.flake) nixosModules;
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.workloads-egress = pkgs.testers.runNixOSTest {
        name = "workloads-egress";

        nodes.machine =
          { lib, ... }:
          {
            imports = [ nixosModules."workloads-networks" ];

            options.programs.cloudflare-warp.extended.enable = lib.mkEnableOption "WARP";

            config = {
              _module.args.hostName = "machine";
              networking.nftables.enable = true;

              workloads.networks = {
                out.id = 1;
                off = {
                  id = 2;
                  egress = "none";
                };
              };

              # routed counts guest packets the kernel routes to the uplink, before
              # inet workload sees them; the rest count what leaves the host, warp
              # only once the tunnel end has replied.
              networking.nftables.tables.probe = {
                family = "inet";
                content = ''
                  counter routed {}
                  counter uplink {}
                  counter warp {}
                  counter sealed {}

                  chain forward {
                    type filter hook forward priority filter - 10; policy accept;
                    oifname != "vn-*" oifname != "CloudflareWARP" ip saddr 172.16.0.0/16 counter name routed
                  }

                  chain postrouting {
                    type filter hook postrouting priority srcnat - 1; policy accept;
                    oifname != "vn-*" oifname != "CloudflareWARP" ip saddr 172.16.0.0/16 counter name uplink
                    oifname "CloudflareWARP" ip saddr 172.16.1.0/24 ct state established counter name warp
                    oifname "CloudflareWARP" ip saddr 172.16.2.0/24 counter name sealed
                  }
                '';
              };
            };
          };

        testScript = ''
          import json

          def count(name):
              out = json.loads(machine.succeed(f"nft -j list counter inet probe {name}"))
              return next(item["counter"]["packets"] for item in out["nftables"] if "counter" in item)

          def client(name, net):
              machine.succeed(
                  f"ip link add vn-{name} type bridge",
                  f"ip addr add 172.16.{net}.1/24 dev vn-{name}",
                  f"ip link set vn-{name} up",
                  f"ip netns add {name}",
                  f"ip link add {name}0 type veth peer name eth0 netns {name}",
                  f"ip link set {name}0 master vn-{name} up",
                  f"ip -n {name} addr add 172.16.{net}.10/24 dev eth0",
                  f"ip -n {name} link set eth0 up",
                  f"ip -n {name} route add default via 172.16.{net}.1",
                  f"systemd-run --unit probe-{name} ${pkgs.iproute2}/bin/ip netns exec {name} ${pkgs.iputils}/bin/ping -q -i 0.005 1.1.1.1",
              )

          machine.wait_for_unit("multi-user.target")
          machine.succeed("ip route replace default via 192.168.1.254 dev eth1 onlink")
          machine.wait_until_succeeds("ip rule | grep -F 'iif vn-off'", timeout=60)

          # The tunnel end answers, so the warp flow is established before the band
          # goes. warp-svc adds its rule without a preference, one below the lowest in use.
          machine.succeed(
              "ip netns add warp",
              "ip link add CloudflareWARP type veth peer name eth0 netns warp",
              "ip addr add 10.99.0.1/30 dev CloudflareWARP",
              "ip link set CloudflareWARP up",
              "ip -n warp addr add 10.99.0.2/30 dev eth0",
              "ip -n warp addr add 1.1.1.1/32 dev lo",
              "ip -n warp link set lo up",
              "ip -n warp link set eth0 up",
              "ip route add default via 10.99.0.2 dev CloudflareWARP table 65743",
              "ip rule add not fwmark 0x100cf lookup 65743",
          )
          warp_rule = "31014:\tnot from all fwmark 0x100cf lookup 65743"
          assert warp_rule in machine.succeed("ip rule"), "WARP's rule is not inside the band"

          client("out", 1)
          client("off", 2)

          with subtest("warp traffic leaves through the tunnel, none traffic through nothing"):
              machine.wait_until_succeeds("nft list counter inet probe warp | grep -Eq 'packets [0-9]{3,}'", timeout=60)
              assert count("sealed") == 0, "a none network reached WARP through its host rule"

          with subtest("restarts keep the band and a foreign rule in it"):
              machine.succeed("ip route flush table 65743")
              before = count("routed")
              machine.succeed("for i in $(seq 20); do systemctl restart workload-egress.service; done")
              assert count("routed") == before, "a restart opened the band"
              assert warp_rule in machine.succeed("ip rule"), "a restart deleted WARP's rule"

          with subtest("the outbound chain drops guest traffic, established flows included, once the band is lost"):
              machine.succeed(
                  "ip rule show | awk -F: '$1 >= 31000 && $1 <= 31999 && /iif vn-/ { print \"rule del pref \" $1 }' | ip -batch -"
              )
              machine.wait_until_succeeds("nft list counter inet probe routed | grep -Eq 'packets [0-9]{3,}'", timeout=60)
              machine.succeed("systemctl restart workload-egress.service")
              machine.fail("ip route get 1.1.1.1 from 172.16.1.10 iif vn-out")

          assert count("uplink") == 0, "guest traffic left through the uplink"
          assert count("sealed") == 0, "a none network reached WARP"
        '';
      };
    };
}
