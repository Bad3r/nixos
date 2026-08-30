{
  flake.nixosModules.hosts-common.imports = [
    {
      # Keep controller access independent from the optional nvme-cli package:
      # smartmontools uses the same character devices for controller-level logs.
      services.udev.extraRules = ''
        SUBSYSTEM=="nvme", KERNEL=="nvme[0-9]*", GROUP="disk", MODE="0660"
        SUBSYSTEM=="nvme-generic", KERNEL=="ng[0-9]*", GROUP="disk", MODE="0660"
      '';
    }
  ];
}
