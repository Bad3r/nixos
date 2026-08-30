_:
let
  body =
    {
      config,
      lib,
      ...
    }:
    {
      # libata refuses ATA TRUSTED SEND/RECEIVE unless this is set, which is the
      # only path Opal traffic takes to a SATA drive. NVMe goes through admin
      # security send/receive instead and is unaffected.
      boot.kernelParams = [ "libata.allow_tpm=1" ];

      # Keep controller access independent from the optional nvme-cli package:
      # smartmontools uses the same character devices for controller-level logs.
      services.udev.extraRules = ''
        SUBSYSTEM=="nvme", KERNEL=="nvme[0-9]*", GROUP="disk", MODE="0660"
        SUBSYSTEM=="nvme-generic", KERNEL=="ng[0-9]*", GROUP="disk", MODE="0660"
      '';

      # A switch only restarts systemd-udevd, and udev applies rules to new
      # uevents only, so nodes enumerated at boot keep the kernel default
      # root:root 0600 until a reboot. `udevadm trigger` needs root, which the
      # `disk` members this grant targets do not have.
      systemd.services.nvme-char-device-permissions = lib.mkIf config.services.udev.enable {
        description = "Re-apply udev permissions to existing NVMe character devices";
        wants = [ "systemd-udevd.service" ];
        after = [ "systemd-udevd.service" ];
        wantedBy = [ "multi-user.target" ];
        restartTriggers = [ config.environment.etc."udev/rules.d".source ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          # `change` reaches udev_node_apply_permissions(); only the SELinux
          # relabel is add-only. Namespace nodes are SUBSYSTEM=block and stay
          # untouched, so the root filesystem is never retriggered.
          ExecStart = "${config.systemd.package}/bin/udevadm trigger --settle --action=change --subsystem-match=nvme --subsystem-match=nvme-generic";
        };
      };
    };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
