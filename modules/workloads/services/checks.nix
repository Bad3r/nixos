# NixOS VM test for declared Podman networks and services. CI only forces its
# drvPath; run it with
#   nix build "path:.#checks.x86_64-linux.workloads-services"
{
  config,
  metaOwner,
  nixosAppHelpers,
  ...
}:
let
  inherit (config.flake) nixosModules;
  inherit (nixosAppHelpers) getApp;
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.workloads-services = pkgs.testers.runNixOSTest {
        name = "workloads-services";

        nodes.machine =
          { lib, ... }:
          {
            imports = [
              nixosModules."workloads-networks"
              nixosModules."workloads-services"
              (getApp "podman")
              (getApp "docker-compose")
            ];

            # warp-svc needs an account; the stub only accepts the row the warp egress turns on.
            options.programs.cloudflare-warp.extended.enable = lib.mkEnableOption "the WARP row";

            config = {
              _module.args = {
                hostName = "machine";
                inherit metaOwner;
              };

              users.users.${metaOwner.username} = {
                isNormalUser = true;
                uid = 1000;
              };

              networking.nftables.enable = true;
              networking.hosts."10.9.9.9" = [ "mesh-marker.internal" ];
              virtualisation.memorySize = 1536;
              systemd.tmpfiles.rules = [ "d /var/lib/workloads-test 0755 root root -" ];

              # A spec change: none turns DNS off and drops the MTU to 1500.
              specialisation.none.configuration.workloads.networks.test.egress = "none";

              workloads.networks.test = {
                id = 5;
                podman.enable = true;
              };

              workloads.services.web = {
                image = "workloads-httpd:test";
                imageFile = pkgs.dockerTools.buildImage {
                  name = "workloads-httpd";
                  tag = "test";
                  copyToRoot = pkgs.buildEnv {
                    name = "workloads-httpd-root";
                    paths = [
                      pkgs.busybox
                      (pkgs.writeTextDir "www/index.html" "workloads-ok")
                    ];
                  };
                  config.Cmd = [
                    "httpd"
                    "-f"
                    "-p"
                    "80"
                    "-h"
                    "/www"
                  ];
                };
                network = "test";
                address = 10;
                volumes = [ "/var/lib/workloads-test:/data:idmap" ];
                ports = [
                  {
                    host = 8080;
                    container = 80;
                  }
                ];
                autostart = true;
              };
            };
          };

        testScript = ''
          def label():
              return machine.succeed(
                  "podman network inspect --format '{{.ID}} {{index .Labels \"io.github.bad3r.nixos.workloads\"}}' test"
              ).split()

          machine.wait_for_unit("podman-svc-web.service")

          machine.succeed("ip -4 -o addr show dev vn-test | grep -F 'inet 172.16.5.1/24'")
          machine.succeed("ip -o link show dev vn-test | grep -F 'mtu 1240'")
          address = machine.succeed(
              "podman inspect --format '{{.NetworkSettings.Networks.test.IPAddress}}' svc-web"
          ).strip()
          assert address == "172.16.5.10", address

          machine.wait_until_succeeds("curl -sf http://127.0.0.1:8080/ | grep -Fx workloads-ok")
          tables = machine.succeed("nft list tables")
          assert "netavark" not in tables, tables

          with subtest("aardvark-dns on the gateway is the only resolver and forwards to WARP"):
              resolv = machine.succeed("podman exec svc-web cat /etc/resolv.conf")
              servers = [line.split()[1] for line in resolv.splitlines() if line.startswith("nameserver")]
              assert servers == ["172.16.5.1"], resolv
              machine.succeed("podman exec svc-web nslookup svc-web 172.16.5.1 | grep -F 172.16.5.10")
              upstream = machine.succeed("podman network inspect --format '{{.NetworkDNSServers}}' test").strip()
              assert upstream == "[127.0.2.2 127.0.2.3]", upstream

          with subtest("the host's /etc/hosts stays out"):
              hosts = machine.succeed("podman exec svc-web cat /etc/hosts")
              assert "mesh-marker" not in hosts, hosts

          with subtest("container root is not host root, and idmap maps it back"):
              uid_map = machine.succeed("podman exec svc-web cat /proc/self/uid_map").split()
              assert uid_map[0] == "0" and int(uid_map[1]) >= 1879048192, uid_map
              machine.succeed("podman exec svc-web touch /data/probe")
              owner = machine.succeed("stat -c %u /var/lib/workloads-test/probe").strip()
              assert owner == "0", owner

          with subtest("an unchanged network is kept"):
              before = label()
              machine.succeed("systemctl restart workloads-podman-net-test.service")
              machine.wait_for_unit("podman-svc-web.service")
              assert label() == before

          with subtest("a removed network returns on the next container start"):
              machine.succeed("systemctl stop podman-svc-web.service")
              machine.succeed("podman network rm test")
              machine.succeed("systemctl start podman-svc-web.service")
              machine.wait_until_succeeds("curl -sf http://127.0.0.1:8080/ | grep -Fx workloads-ok")

          with subtest("a spec change recreates the network"):
              before = label()
              machine.succeed("/run/current-system/specialisation/none/bin/switch-to-configuration test")
              machine.wait_for_unit("podman-svc-web.service")
              after = label()
              assert after[0] != before[0] and after[1] != before[1], (before, after)
              machine.wait_until_succeeds("ip -o link show dev vn-test | grep -F 'mtu 1500'")
              machine.wait_until_succeeds("curl -sf http://127.0.0.1:8080/ | grep -Fx workloads-ok")
              # --dns=none leaves no resolv.conf; grep fails on a missing file too.
              machine.fail("podman exec svc-web grep '^nameserver' /etc/resolv.conf")
              upstream = machine.succeed("podman network inspect --format '{{.NetworkDNSServers}}' test").strip()
              assert upstream == "[]", upstream

          with subtest("an unlabelled network of a declared name is refused"):
              machine.succeed("systemctl stop podman-svc-web.service")
              machine.succeed("podman network rm test && podman network create test")
              machine.fail("systemctl restart workloads-podman-net-test.service")
              machine.succeed(
                  "journalctl -u workloads-podman-net-test.service"
                  " | grep -F 'Podman network test exists without the io.github.bad3r.nixos.workloads label'"
              )
              assert label()[1:] == [], label()

          with subtest("a bridge no labelled network owns is refused"):
              machine.succeed("podman network rm test")
              machine.fail("ip link show dev vn-test")
              machine.succeed("ip link add vn-test type bridge")
              machine.fail("systemctl restart workloads-podman-net-test.service")
              machine.succeed(
                  "journalctl -u workloads-podman-net-test.service"
                  " | grep -F 'vn-test exists but no labelled Podman network owns it; remove it first'"
              )
              machine.fail("podman network exists test")
        '';
      };
    };
}
