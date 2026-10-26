# Needs /dev/kvm with nested virtualization, so CI only forces its drvPath.
#   nix build "path:.#checks.x86_64-linux.sbx-gui"
{ metaOwner, nixosAppHelpers, ... }:
let
  owner = metaOwner.username;
  state = "/home/${owner}/.local/share/sbx";
in
{
  perSystem =
    { config, pkgs, ... }:
    let
      base = config.workloads.artifacts.sbx-nixos-gui;
    in
    {
      checks.sbx-gui = pkgs.testers.runNixOSTest {
        name = "sbx-gui";

        nodes.machine =
          { config, ... }:
          {
            imports = [
              (nixosAppHelpers.getApp "libvirt")
              (nixosAppHelpers.getApp "sbx")
            ];

            _module.args = {
              hostName = "machine";
              inherit metaOwner;
            };

            virtualisation = {
              cores = 2;
              memorySize = 3072;
              diskSize = 4096;
              additionalPaths = [ base ];
            };
            boot = {
              # sbx-qemu needs vsock network namespaces, which the latest kernel has.
              kernelPackages = pkgs.linuxPackages_latest;
              kernelModules = [ "vhost_vsock" ];
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
                memory = 2;
                sliceMemory = 3;
                cpus = "0-1";
                ttl = 1;
                maxTtl = 24;
                disk = 16;
                minFree = 1;
              };
              sandbox = {
                memory = 512;
                guiMemory = 1536;
                maxMemory = 2048;
                disk = 1;
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

        testScript =
          { nodes, ... }:
          let
            firmware = "${nodes.machine.programs.libvirt.extended.qemuPackage}/share/qemu/firmware";
          in
          ''
            import json
            import shlex
            import string

            def as_owner(command):
                return f"runuser -u ${owner} -- env XDG_RUNTIME_DIR=/run/user/1000 LIBVIRT_AUTOSTART=0 {command}"

            def sbx(*argv):
                return json.loads(machine.succeed(as_owner(shlex.join(["sbx", "--json", *argv]))))

            machine.wait_for_unit("multi-user.target")
            machine.wait_for_unit("user@1000.service")
            # The Home Manager part links these descriptors and builds the base out-link.
            machine.succeed(
                as_owner("mkdir -p /home/${owner}/.config/qemu/firmware ${state}/bases"),
                as_owner("ln -s ${firmware}/60-edk2-x86_64.json /home/${owner}/.config/qemu/firmware/"),
                as_owner("nix-store --add-root ${state}/bases/nixos-gui --realise ${base}"),
            )

            with subtest("--gui boots the GUI base"):
                created = sbx("create", "nixos", "--gui", "--name", "g", "--ttl", "30m")
                assert (created["base"], created["memory_mib"]) == ("nixos-gui", 1536), created

            with subtest("root reaches the session's display, where a terminal has focus"):
                try:
                    machine.wait_until_succeeds(as_owner("sbx exec g -- xdotool search --onlyvisible --class xterm"), timeout=180)
                except Exception:
                    diagnose = (
                        "systemctl --failed; "
                        "journalctl -b -u display-manager -u accounts-daemon --no-pager | tail -60; "
                        "tail -n 40 /var/log/lightdm/*.log /home/sbx/.xsession-errors; "
                        "ps -eo user,stat,args; xdotool search --name . getwindowname %@"
                    )
                    print(machine.execute(as_owner(shlex.join(["sbx", "exec", "g", "--", "sh", "-c", diagnose])))[1])
                    raise
                title = sbx("exec", "g", "--", "xdotool", "getactivewindow", "getwindowname")["stdout"]
                assert title.startswith("sbx@sbx"), title

            with subtest("type and key deliver every printable ASCII character"):
                text = "".join(c for c in string.printable if c not in "\t\n\r\x0b\x0c")
                sbx("type", "g", "cat > ~/typed\n")
                assert sbx("type", "g", text + "\n") == {"sandbox": "g", "characters": len(text) + 1}
                assert sbx("key", "g", "ctrl+d") == {"sandbox": "g", "keys": ["ctrl+d"]}
                machine.wait_until_succeeds(as_owner("sbx exec g -- test -s /home/sbx/typed"), timeout=30)
                typed = sbx("exec", "g", "--", "cat", "/home/sbx/typed")["stdout"]
                assert typed == text + "\n", typed

            def typed(path, *steps):
                """Run cat > path in the focused terminal, press steps, end it, and read the file."""
                sbx("type", "g", f"cat > {path}\n")
                for step in steps:
                    step()
                sbx("key", "g", "ctrl+d")
                machine.wait_until_succeeds(as_owner(f"sbx exec g -- test -s {path}"), timeout=30)
                return sbx("exec", "g", "--", "cat", path)["stdout"]

            def caps_led():
                leds = sbx("exec", "g", "--", "sh", "-c", "cat /sys/class/leds/input*::capslock/brightness")
                return any(int(value) for value in leds["stdout"].split())

            with subtest("type keeps its case under Caps Lock"):
                text = typed(
                    "/home/sbx/caps",
                    lambda: sbx("key", "g", "capslock"),
                    lambda: sbx("type", "g", "abc ABC\n"),
                )
                sbx("key", "g", "capslock")
                assert text == "abc ABC\n", text

            with subtest("type sends Unicode"):
                text = typed("/home/sbx/unicode", lambda: sbx("type", "g", "h\u00e9llo \u2713\n"))
                assert text == "h\u00e9llo \u2713\n", text

            with subtest("the Caps Lock LED follows X, and --mode keys types through it"):
                def lit():
                    sbx("key", "g", "capslock")
                    assert caps_led(), "the LED stays dark with Caps Lock on"
                    sbx("type", "g", "--mode", "keys", "abc ABC\n")
                text = typed("/home/sbx/keys", lit)
                assert caps_led(), "keys mode left Caps Lock off"
                sbx("key", "g", "capslock")
                assert not caps_led(), "the LED stays lit with Caps Lock off"
                assert text == "abc ABC\n", text

            with subtest("window wait finds the terminal, and the pointer clicks it"):
                (window,) = sbx("window", "wait", "g", "--class", "^xterm$", "--timeout", "60s")["windows"]
                assert window["name"].startswith("sbx@sbx"), window
                listed = sbx("window", "list", "g")["windows"]
                assert window in listed, listed
                assert sbx("window", "focus", "g", "--id", str(window["id"]))["window"] == window
                geometry = window["geometry"]
                x, y = geometry["x"] + geometry["width"] // 2, geometry["y"] + geometry["height"] // 2
                clicked = sbx("mouse", "g", "--to", f"{x},{y}", "--click", "left")
                assert clicked == {"sandbox": "g", "x": x, "y": y, "click": "left", "double": False}, clicked
                location = sbx("exec", "g", "--", "xdotool", "getmouselocation", "--shell")["stdout"]
                assert f"X={x}\nY={y}\n" in location, location

            with subtest("screenshot OCR reads what was typed"):
                sbx("type", "g", "clear; echo SBXOCROK\n")
                machine.wait_until_succeeds(
                    as_owner("sbx --json screenshot g --ocr | grep -q SBXOCROK"), timeout=60
                )

            with subtest("screenshots get their own files, and --to keeps one"):
                first, second = sbx("screenshot", "g")["path"], sbx("screenshot", "g")["path"]
                assert first != second, first
                machine.succeed(as_owner("mkdir -p /home/${owner}/trees/shots"))
                kept = sbx("screenshot", "g", "--to", "/home/${owner}/trees/shots")["path"]
                assert kept.startswith("/home/${owner}/trees/shots/screenshot-"), kept

            with subtest("destroy removes the sandbox"):
                sbx("destroy", "g")
                machine.fail("test -e ${state}/g")
                assert sbx("list") == []
                machine.succeed(f"test -s {kept}")
          '';
      };
    };
}
