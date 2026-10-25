# Needs /dev/kvm with nested virtualization, so CI only forces its drvPath.
#   nix build "path:.#checks.x86_64-linux.sbx-vsock"
{
  config,
  metaOwner,
  nixosAppHelpers,
  ...
}:
let
  flakeModules = config.flake.nixosModules;
  owner = metaOwner.username;
  home = "/home/${owner}";
in
{
  perSystem =
    { config, pkgs, ... }:
    let
      base = config.workloads.artifacts.sbx-nixos;
      python = pkgs.python3.interpreter;
      listener = pkgs.writeText "vsock-listener.py" ''
        import socket
        import sys

        cid = socket.VMADDR_CID_ANY if sys.argv[1] == "any" else int(sys.argv[1])
        server = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
        server.bind((cid, int(sys.argv[2])))
        server.listen()
        while True:
            peer, _ = server.accept()
            peer.sendall(sys.argv[3].encode() + b"\n")
            peer.close()
      '';
      # Runs in the guest; prints the listener's reply or the connect error's type.
      probe = pkgs.writeText "vsock-probe.py" ''
        import socket
        import sys

        client = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
        client.settimeout(10)
        try:
            client.connect((int(sys.argv[1]), int(sys.argv[2])))
            print(client.recv(64).decode().strip())
        except OSError as error:
            print(type(error).__name__)
      '';
    in
    {
      checks.sbx-vsock = pkgs.testers.runNixOSTest {
        name = "sbx-vsock";

        nodes.machine =
          { config, lib, ... }:
          {
            imports = [
              (nixosAppHelpers.getApp "libvirt")
              (nixosAppHelpers.getApp "sbx")
              flakeModules."workloads-networks"
              flakeModules."workloads-vms"
            ];

            # networks.nix turns WARP on for warp networks; this test declares none.
            options.programs.cloudflare-warp.extended.enable = lib.mkEnableOption "WARP";

            config = {
              _module.args = {
                hostName = "machine";
                inherit metaOwner;
              };

              # The latest kernel has vsock network namespaces.
              boot.kernelPackages = pkgs.linuxPackages_latest;
              virtualisation = {
                cores = 2;
                memorySize = 3072;
                diskSize = 4096;
                additionalPaths = [ base ];
              };
              users.users.${owner} = {
                isNormalUser = true;
                uid = 1000;
                # Keeps the user manager, and so sbx-libvirt, running without a login.
                linger = true;
              };
              programs.libvirt.extended.enable = true;
              programs.sbx.extended = {
                enable = true;
                package = pkgs.callPackage ../../../packages/sbx { };
                limits = {
                  running = 1;
                  memory = 1;
                  sliceMemory = 2;
                  cpus = "0-1";
                  ttl = 1;
                  maxTtl = 24;
                  disk = 20;
                  minFree = 1;
                };
                sandbox = {
                  memory = 1024;
                  maxMemory = 1024;
                  disk = 1;
                };
              };
              networking.nftables.enable = true;
              workloads.networks.sbx = {
                id = 6;
                egress = "none";
                isolatePeers = true;
                libvirt = {
                  enable = true;
                  uuid = "00000000-0000-4000-8000-0000000000bb";
                  dhcp = {
                    start = 2;
                    end = 254;
                  };
                  sessionAttach = true;
                };
              };
              # What the sbx Home Manager part declares.
              systemd.user.services.sbx-libvirt = {
                description = "libvirt session daemon for sbx sandboxes";
                serviceConfig = {
                  Type = "notify";
                  ExecStart = "${config.programs.libvirt.extended.package}/bin/virtqemud --timeout 600";
                  Slice = "sbx.slice";
                  KillMode = "process";
                };
              };
            };
          };

        testScript =
          { nodes, ... }:
          let
            firmware = "${nodes.machine.programs.libvirt.extended.qemuPackage}/share/qemu/firmware";
          in
          ''
            import json

            def as_owner(command):
                return f"runuser -u ${owner} -- env XDG_RUNTIME_DIR=/run/user/1000 TMPDIR=${home}/tmp {command}"

            def sbx(command):
                return json.loads(machine.succeed(as_owner(f"sbx --json {command}")))

            def sbx_status(command):
                status, output = machine.execute(as_owner(f"sbx --json {command}"))
                return status, json.loads(output)

            def listen(unit, cid, port, reply, wrap=""):
                machine.succeed(f"systemd-run --unit {unit} --uid ${owner} {wrap} ${python} ${listener} {cid} {port} {reply}")
                listening = as_owner(f"{wrap} ss -H -l --vsock") if wrap else "ss -H -l --vsock"
                machine.wait_until_succeeds(f"{listening} | grep -F ':{port} '", timeout=10)

            def guest_reaches(name, cid, port):
                result = sbx(f"exec {name} -- python3 /root/probe.py {cid} {port}")
                assert result["exit_code"] == 0, result
                return result["stdout"].strip()

            def enter(name):
                pid = machine.succeed(f"cat /run/user/1000/libvirt/qemu/run/sbx-{name}.pid").strip()
                return f"nsenter --target {pid} --user --net --preserve-credentials"

            machine.wait_for_unit("multi-user.target")
            machine.wait_for_unit("user@1000.service")
            machine.succeed(as_owner(
                "sh -c 'mkdir -p ${home}/tmp ${home}/.config/qemu/firmware ${home}/.local/share/sbx/bases"
                " && ln -s ${firmware}/50-edk2-x86_64-secure.json ${firmware}/60-edk2-x86_64.json ${home}/.config/qemu/firmware/"
                " && ln -s ${base} ${home}/.local/share/sbx/bases/nixos"
                " && cp ${probe} ${home}/tmp/probe.py'"
            ))

            with subtest("a host listener does not stop create"):
                machine.succeed("modprobe -a vhost_vsock vsock_loopback")
                listen("before", "any", 5554, "host")
                created = sbx("create nixos --name v --ttl 30m")
                assert created["cid"] is not None, created

            with subtest("exec and cp reach the guest"):
                sbx("cp ${home}/tmp/probe.py v:/root/probe.py")
                result = sbx("exec v -- cat /etc/hostname")
                assert (result["exit_code"], result["stdout"], result["stderr"]) == (0, "sbx\n", ""), result
                assert not (result["timed_out"] or result["killed"] or result["signal"] or result["transport_error"]), result

            with subtest("timed_out follows the host deadline, and SIGKILL follows an ignored SIGTERM"):
                status, result = sbx_status("exec v --timeout 30s -- sh -c 'exit 124'")
                assert status == 124 and result["exit_code"] == 124 and not result["timed_out"], result
                stubborn = "import signal, time; signal.signal(signal.SIGTERM, signal.SIG_IGN); print('started', flush=True); time.sleep(60)"
                status, result = sbx_status(f"exec v --timeout 1s -- python3 -c \"{stubborn}\"")
                assert status == 124, (status, result)
                assert result["timed_out"] and result["killed"] and result["signal"] == "KILL", result
                assert result["exit_code"] is None and result["stdout"] == "started\n", result

            with subtest("host listeners started after the sandbox stay unreachable"):
                listen("after-any", "any", 5555, "host")
                listen("after-host", 2, 5556, "host")
                # The listeners accept in the host's own namespace.
                assert machine.succeed("${python} ${probe} 1 5555").strip() == "host"
                for port in (5554, 5555, 5556):
                    assert guest_reaches("v", 2, port) == "ConnectionResetError", port

            with subtest("a listener inside the sandbox namespace is reachable"):
                listen("inside", "any", 5557, "inside", wrap=enter("v"))
                assert guest_reaches("v", 2, 5557) == "inside"

            with subtest("a sandbox restored from its managed save gets a new local namespace"):
                saved = enter("v")
                machine.succeed(as_owner("sbx sleep save"))
                listen("saved-any", "any", 5558, "host")
                machine.succeed(as_owner("sbx sleep restore"))
                restored = enter("v")
                assert restored != saved, restored
                listen("restored-host", 2, 5559, "host")
                for port in (5554, 5555, 5556, 5558, 5559):
                    assert guest_reaches("v", 2, port) == "ConnectionResetError", port
                listen("restored-inside", "any", 5560, "inside", wrap=restored)
                assert guest_reaches("v", 2, 5560) == "inside"

            with subtest("an egress sandbox gets its lease and no host vsock listener"):
                sbx("destroy v")
                machine.wait_for_unit("workloads-vm-net-sbx.service")
                created = sbx("create nixos --name e --net egress --ttl 30m")
                assert created["address"].startswith("172.16.6."), created
                sbx("cp ${home}/tmp/probe.py e:/root/probe.py")
                for port in (5554, 5555, 5556):
                    assert guest_reaches("e", 2, port) == "ConnectionResetError", port
                sbx("destroy e")
          '';
      };
    };
}
