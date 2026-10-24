# Needs /dev/kvm, so CI only forces its drvPath.
{
  config,
  metaOwner,
  nixosAppHelpers,
  ...
}:
let
  flakeModules = config.flake.nixosModules;
  libvirtApp = nixosAppHelpers.getApp "libvirt";
in
{
  perSystem =
    { lib, pkgs, ... }:
    let
      domain =
        name: id:
        pkgs.writeText "${name}.xml" ''
          <domain type="qemu">
            <name>${name}</name>
            <uuid>00000000-0000-4000-8000-00000000000${toString id}</uuid>
            <memory unit="MiB">64</memory>
            <os>
              <type arch="x86_64" machine="q35">hvm</type>
            </os>
            <devices>
              <channel type="unix">
                <target type="virtio" name="org.qemu.guest_agent.0"/>
              </channel>
            </devices>
          </domain>
        '';
    in
    {
      checks.workloads-vm-sleep = pkgs.testers.runNixOSTest {
        name = "workloads-vm-sleep";

        nodes.machine =
          { lib, ... }:
          {
            imports = [
              libvirtApp
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
              networking.nftables.enable = true;
              users.users.${metaOwner.username}.isNormalUser = true;
              programs.libvirt.extended.enable = true;
            };
          };

        testScript =
          { nodes, ... }:
          let
            hook =
              unit: step:
              lib.concatStringsSep " && " nodes.machine.systemd.services.${unit}.serviceConfig.${step};
          in
          ''
            def state(name):
                return machine.succeed(f"virsh domstate {name}").strip()

            def states():
                return {name: state(name) for name in ["alpha", "beta"]}

            machine.wait_for_unit("libvirtd.service")
            machine.succeed(
                "virsh define ${domain "alpha" 1}",
                "virsh define ${domain "beta" 2}",
                "virsh start alpha",
                "virsh start --paused beta",
            )

            with subtest("suspend pauses running guests and resumes only those"):
                machine.succeed("${hook "systemd-suspend" "ExecStartPre"}")
                assert states() == {"alpha": "paused", "beta": "paused"}, states()
                # No agent runs in the guest, so the clock resync only warns.
                output = machine.succeed("${hook "systemd-suspend" "ExecStopPost"}")
                assert "alpha keeps a stale clock" in output, output
                assert states() == {"alpha": "running", "beta": "paused"}, states()
                machine.fail("test -e /run/workloads-vm-sleep/paused")

            with subtest("hibernation managed-saves active guests and restores them"):
                machine.succeed("${hook "systemd-hibernate" "ExecStartPre"}")
                saved = machine.succeed("virsh list --all --with-managed-save --name").split()
                assert sorted(saved) == ["alpha", "beta"], saved
                machine.succeed("${hook "systemd-hibernate" "ExecStopPost"}")
                assert states() == {"alpha": "running", "beta": "paused"}, states()

            with subtest("a failed save aborts and the guests saved before it are restored"):
                # libvirt refuses to managed-save a transient domain.
                machine.succeed("virsh create ${domain "gamma" 3}")
                status, output = machine.execute("${hook "systemd-hibernate" "ExecStartPre"} 2>&1")
                assert status == 1 and "transient" in output, output
                assert states() == {"alpha": "shut off", "beta": "shut off"}, states()
                machine.succeed("${hook "systemd-hibernate" "ExecStopPost"}")
                assert states() == {"alpha": "running", "beta": "paused"}, states()
                assert state("gamma") == "running"
          '';
      };
    };
}
