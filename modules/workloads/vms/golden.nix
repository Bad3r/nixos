_:
let
  goldenModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      guests = lib.filterAttrs (_: guest: guest.ensure == "present") config.workloads.guests;
      python = pkgs.python3.withPackages (ps: [ ps.libvirt ]);

      manifest = pkgs.writeText "workloads-golden.json" (
        builtins.toJSON (
          lib.mapAttrs (_: guest: {
            inherit (guest) uuid stateDir;
            nvram = guest.nvramPath;
            disks = map (disk: "${guest.stateDir}/${disk}.qcow2") (lib.attrNames guest.disks);
          }) guests
        )
      );
    in
    {
      config = lib.mkIf (guests != { }) {
        # Started by hand only: `systemctl start workloads-golden@<guest>`.
        systemd.services."workloads-golden@" = {
          description = "Copy the shut-off %i workload guest to its golden directory";
          requires = [ "libvirtd.service" ];
          after = [ "libvirtd.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${python.interpreter} -I ${./_reconciler.py} golden ${manifest} %i --directory ${config.workloads.goldenDir}";
          };
        };
      };
    };
in
{
  flake.nixosModules."workloads-vms" = goldenModule;
}
