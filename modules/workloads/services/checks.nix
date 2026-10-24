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
              nixosModules."workloads-vms"
              (getApp "podman")
              (getApp "libvirt")
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
              virtualisation.memorySize = 1536;

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
          machine.wait_for_unit("podman-svc-web.service")

          machine.succeed("ip -4 -o addr show dev vn-test | grep -F 'inet 172.16.5.1/24'")
          machine.succeed("ip -o link show dev vn-test | grep -F 'mtu 1240'")
          address = machine.succeed(
              "podman inspect --format '{{.NetworkSettings.Networks.test.IPAddress}}' svc-web"
          ).strip()
          assert address == "172.16.5.10", address

          machine.wait_until_succeeds("curl -sf http://127.0.0.1:8080/ | grep -Fx workloads-ok")
          machine.fail("nft list tables | grep -F netavark")

          with subtest("aardvark-dns on the gateway is the only resolver"):
              resolv = machine.succeed("podman exec svc-web cat /etc/resolv.conf")
              servers = [line.split()[1] for line in resolv.splitlines() if line.startswith("nameserver")]
              assert servers == ["172.16.5.1"], resolv
              machine.succeed("podman exec svc-web nslookup svc-web 172.16.5.1 | grep -F 172.16.5.10")

          with subtest("container root is not host root"):
              uid_map = machine.succeed("podman exec svc-web cat /proc/self/uid_map").split()
              assert uid_map[0] == "0" and int(uid_map[1]) >= 1879048192, uid_map

          with subtest("an unchanged network is kept"):
              network_id = machine.succeed("podman network inspect --format '{{.ID}}' test")
              machine.succeed("systemctl restart workloads-podman-net-test.service")
              assert machine.succeed("podman network inspect --format '{{.ID}}' test") == network_id

          with subtest("an unlabelled network of a declared name is refused"):
              machine.succeed("systemctl stop podman-svc-web.service")
              machine.succeed("podman network rm test && podman network create test")
              machine.fail("systemctl restart workloads-podman-net-test.service")
        '';
      };
    };
}
