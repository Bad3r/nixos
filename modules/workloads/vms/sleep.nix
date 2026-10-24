_:
let
  sleepModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      python = pkgs.python3.withPackages (ps: [ ps.libvirt ]);
      vmSleep = "${python.interpreter} -I ${./_vm-sleep.py}";

      hibernate = {
        pre = "save";
        post = "restore";
      };
      phases = {
        systemd-suspend = {
          pre = "pause";
          post = "resume";
        };
        systemd-hibernate = hibernate;
        systemd-hybrid-sleep = hibernate;
        systemd-suspend-then-hibernate = hibernate;
      };

      # Covers qemu:///system; session guests need the same phase run per user.
      hook = phase: [ "${vmSleep} ${phase}" ];
    in
    {
      # ExecStopPost, unlike ExecStartPost, also runs after a failed or aborted transition.
      config = lib.mkIf config.programs.libvirt.extended.enable {
        systemd.services = lib.mapAttrs (_: phase: {
          serviceConfig = {
            ExecStartPre = hook phase.pre;
            # A failing post command skips the ones after it; this one always exits 0.
            ExecStopPost = lib.mkBefore (hook phase.post);
          };
        }) phases;
      };
    };
in
{
  flake.nixosModules."workloads-vms" = sleepModule;
}
