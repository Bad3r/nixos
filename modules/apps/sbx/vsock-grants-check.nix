# Needs /dev/kvm with nested virtualization, so CI only forces its drvPath.
#   nix build "path:.#checks.x86_64-linux.sbx-vsock-grants"
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
      echo = pkgs.writeText "echo-server.py" ''
        import socketserver
        import sys

        class Echo(socketserver.StreamRequestHandler):
            def handle(self):
                for line in self.rfile:
                    self.wfile.write(line)

        socketserver.ThreadingTCPServer.allow_reuse_address = True
        socketserver.ThreadingTCPServer((sys.argv[2], int(sys.argv[1])), Echo).serve_forever()
      '';
      listener = pkgs.writeText "vsock-listener.py" ''
        import socket
        import sys

        cid = socket.VMADDR_CID_ANY if sys.argv[1] == "any" else int(sys.argv[1])
        server = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
        server.bind((cid, int(sys.argv[2])))
        server.listen()
        while True:
            peer, _ = server.accept()
            peer.sendall(b"host\n")
            peer.close()
      '';
      # Counts the AF_VSOCK sockets a process holds, wherever their namespace; the
      # kernel ends the protocol name with a NUL.
      sockets = pkgs.writeText "vsock-sockets.py" ''
        import os
        import sys

        fds = f"/proc/{sys.argv[1]}/fd"
        print(sum(
            os.getxattr(f"{fds}/{fd}", "system.sockprotoname").rstrip(b"\0") == b"AF_VSOCK"
            for fd in os.listdir(fds)
            if os.readlink(f"{fds}/{fd}").startswith("socket:")
        ))
      '';
      # Runs in the guest. `once` prints `echo` for an echoed line, `host` for a host
      # listener, or the connect error's type; `hold` logs one line per round trip
      # until the stream ends, and a stall is told apart from a cut.
      stream = pkgs.writeText "vsock-stream.py" ''
        import socket
        import sys
        import time

        mode, port = sys.argv[1], int(sys.argv[2])
        client = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
        client.settimeout(5)
        try:
            client.connect((2, port))
        except OSError as error:
            print(type(error).__name__)
            sys.exit()
        stream = client.makefile("rwb")
        if mode == "once":
            stream.write(b"x\n")
            stream.flush()
            line = stream.readline()
            print({b"x\n": "echo", b"host\n": "host"}.get(line, repr(line)))
            sys.exit()
        log = open(sys.argv[3], "a", buffering=1)
        while True:
            try:
                stream.write(b"x\n")
                stream.flush()
                line = stream.readline()
            except TimeoutError:
                log.write("stalled\n")
                break
            except OSError as error:
                log.write(f"cut {type(error).__name__}\n")
                break
            if line != b"x\n":
                log.write("cut eof\n")
                break
            log.write("ok\n")
            time.sleep(0.2)
      '';
    in
    {
      checks.sbx-vsock-grants = pkgs.testers.runNixOSTest {
        name = "sbx-vsock-grants";

        nodes.machine =
          { config, lib, ... }:
          let
            sbx = "${config.programs.sbx.extended.finalPackage}/bin/sbx";
          in
          {
            imports = [
              (nixosAppHelpers.getApp "libvirt")
              (nixosAppHelpers.getApp "sbx")
              (nixosAppHelpers.getApp "workloads")
              flakeModules."workloads-networks"
              flakeModules."workloads-vms"
              flakeModules."workloads-sharing"
            ];

            options.programs.cloudflare-warp.extended.enable = lib.mkEnableOption "WARP";

            config = {
              _module.args = {
                hostName = "machine";
                inherit metaOwner;
              };

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
                linger = true;
              };
              programs = {
                libvirt.extended.enable = true;
                sbx.extended = {
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
                workloads.extended.package = pkgs.callPackage ../../../packages/workloads { };
              };
              networking.nftables.enable = true;

              # 8001 answers on loopback too, but no declaration makes it grantable.
              # On 8010 only a loopback-only listener answers, which a bind = any grant must miss.
              workloads = {
                host.services = {
                  dev = {
                    ports = [
                      8000
                      8002
                    ];
                    bind = "loopback";
                    grantable = true;
                  };
                  wide = {
                    ports = [
                      8010
                      8011
                    ];
                    bind = "any";
                    grantable = true;
                  };
                };
                grants.allow = [
                  {
                    from = [ "sbx-*" ];
                    to = [
                      "host:dev"
                      "host:wide"
                    ];
                  }
                ];
              };

              # What the sbx Home Manager part declares.
              systemd.user = {
                services.sbx-libvirt = {
                  description = "libvirt session daemon for sbx sandboxes";
                  serviceConfig = {
                    Type = "notify";
                    ExecStart = "${config.programs.libvirt.extended.package}/bin/virtqemud --timeout 600";
                    Slice = "sbx.slice";
                    KillMode = "process";
                  };
                };
                sockets.sbx-vsock = {
                  wantedBy = [ "sockets.target" ];
                  listenStreams = [ "%t/sbx/vsock.sock" ];
                  socketConfig = {
                    SocketMode = "0600";
                    DirectoryMode = "0700";
                  };
                };
                services.sbx-vsock = {
                  partOf = [ "sbx-vsock.socket" ];
                  serviceConfig = {
                    ExecStart = "${sbx} vsock serve";
                    Restart = "on-failure";
                    LimitNOFILE = 65536;
                    NoNewPrivileges = true;
                    RestrictAddressFamilies = [
                      "AF_UNIX"
                      "AF_INET"
                      "AF_VSOCK"
                    ];
                  };
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
            import shlex
            import time

            def as_owner(command):
                return f"runuser -u ${owner} -- env XDG_RUNTIME_DIR=/run/user/1000 TMPDIR=${home}/tmp {command}"

            def sbx(command):
                return json.loads(machine.succeed(as_owner(f"sbx --json {command}")))

            def workloads(command, code=None):
                status, out = machine.execute(as_owner(f"workloads --json {command}"))
                answer = json.loads(out)
                if code is None:
                    assert status == 0, answer
                else:
                    assert status == 1 and answer["error"]["code"] == code, answer
                return answer

            def grant(target, ttl="30m"):
                return workloads(f"grant sbx-v {target} --ttl {ttl}")["grant"]["id"]

            def in_guest(command):
                result = sbx(f"exec v -- sh -c {shlex.quote(command)}")
                assert result["exit_code"] == 0, result
                return result["stdout"].strip()

            def once(port):
                return in_guest(f"python3 /root/stream.py once {port}")

            def hold(port, name):
                in_guest(f"systemd-run --unit {name} $(command -v python3) /root/stream.py hold {port} /root/{name}.log")
                machine.wait_until_succeeds(as_owner(f"sbx exec v -- grep -q ok /root/{name}.log"), timeout=30)

            def tail(name):
                return in_guest(f"tail -n 1 /root/{name}.log")

            def oks(name):
                return int(in_guest(f"grep -c ok /root/{name}.log"))

            def cut(name, timeout):
                machine.wait_until_succeeds(as_owner(f"sbx exec v -- grep -q '^cut' /root/{name}.log"), timeout=timeout)

            def until(check, timeout):
                deadline = time.monotonic() + timeout
                while not check():
                    assert time.monotonic() < deadline, "timed out"
                    time.sleep(1)

            def proxy_vsock_sockets():
                pid = machine.succeed(as_owner("systemctl --user show -p MainPID --value sbx-vsock.service")).strip()
                return int(machine.succeed(f"${python} ${sockets} {pid}").strip())

            machine.wait_for_unit("multi-user.target")
            machine.wait_for_unit("user@1000.service")
            machine.wait_for_unit("workload-grantd.socket")
            machine.succeed(as_owner(
                "sh -c 'mkdir -p ${home}/tmp ${home}/.config/qemu/firmware ${home}/.local/share/sbx/bases"
                " && ln -s ${firmware}/50-edk2-x86_64-secure.json ${firmware}/60-edk2-x86_64.json ${home}/.config/qemu/firmware/"
                " && ln -s ${base} ${home}/.local/share/sbx/bases/nixos"
                " && cp ${stream} ${home}/tmp/stream.py'"
            ))
            machine.succeed("modprobe -a vhost_vsock vsock_loopback")
            for port, address in ((8000, "127.0.0.1"), (8001, "127.0.0.1"), (8002, "127.0.0.1"), (8010, "127.0.0.1"), (8011, "0.0.0.0")):
                machine.succeed(f"systemd-run --unit echo-{port} ${python} ${echo} {port} {address}")
                machine.wait_for_open_port(port)
            # Host vsock listeners on a granted port and on another; neither may answer a guest.
            machine.succeed("systemd-run --unit vsock-any --uid ${owner} ${python} ${listener} any 8000")
            machine.succeed("systemd-run --unit vsock-host --uid ${owner} ${python} ${listener} 2 8003")
            machine.wait_until_succeeds("ss -H -l --vsock | grep -F ':8003 '", timeout=10)

            sbx("create nixos --name v --ttl 30m")
            sbx("cp ${home}/tmp/stream.py v:/root/stream.py")

            with subtest("a granted port answers inside a sandbox without a network"):
                first = grant("host:dev:8000")
                assert once(8000) == "echo"

            with subtest("ungranted and undeclared ports and host listeners stay unreachable"):
                workloads("grant sbx-v host:dev:8001", code="not-grantable")
                for port in (8001, 8002, 8003):
                    assert once(port) == "ConnectionResetError", port

            with subtest("a bind = any grant reaches a host address, never a loopback-only listener"):
                wide = grant("host:wide")
                assert once(8011) == "echo"
                assert once(8010) == repr(b"")
                workloads(f"revoke {wide}")

            with subtest("revoke cuts that grant's established stream at once, and no other"):
                second = grant("host:dev:8002")
                hold(8000, "first")
                hold(8002, "second")
                workloads(f"revoke {first}")
                cut("first", 5)
                kept = oks("second")
                time.sleep(2)
                assert tail("second") == "ok" and oks("second") > kept
                assert once(8000) == "ConnectionResetError"

            with subtest("TTL expiry cuts an established stream"):
                expiring = grant("host:dev:8000", ttl="60s")
                hold(8000, "expiring")
                assert tail("expiring") == "ok"
                cut("expiring", 90)
                assert once(8000) == "ConnectionResetError"
                assert expiring not in [g["id"] for g in workloads("grants")["grants"]]

            with subtest("a restored sandbox keeps its grant, in its new namespace only"):
                machine.succeed(as_owner("sbx sleep save"))
                machine.succeed(as_owner("sbx sleep restore"))
                until(lambda: machine.execute(as_owner("sbx exec v -- true"))[0] == 0, 60)
                until(lambda: once(8002) == "echo", 30)
                for port in (8000, 8003):
                    assert once(port) == "ConnectionResetError", port
                assert [g["id"] for g in workloads("grants")["grants"]] == [second]

            with subtest("destroy leaves no listener"):
                assert proxy_vsock_sockets() > 0
                sbx("destroy v")
                until(lambda: proxy_vsock_sockets() == 0, 10)
                assert workloads("grants")["grants"] == []
                assert sbx("vsock sync")["grants"] == {}
          '';
      };
    };
}
