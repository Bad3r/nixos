_: {
  configurations.nixos.tpnix.module =
    {
      config,
      lib,
      ...
    }:
    let
      virtCfg = config.tpnix.virtualization;
    in
    {
      options.tpnix.virtualization = {
        libvirt.enable = lib.mkEnableOption "Enable libvirt tooling on the tpnix host" // {
          default = false;
        };
        vmware.enable = lib.mkEnableOption "Enable VMware Workstation on the tpnix host";
        ovftool.enable = lib.mkEnableOption "Install VMware OVF Tool" // {
          default = false;
        };
      };

      config = {
        # Configure virtualization via app modules
        programs = {
          qemu.extended = {
            enable = lib.mkDefault virtCfg.libvirt.enable;
            enableLibvirt = lib.mkDefault virtCfg.libvirt.enable;
          };
          "vmware-workstation".extended = {
            enable = lib.mkDefault virtCfg.vmware.enable;
            enableHost = lib.mkDefault virtCfg.vmware.enable;
          };
          ovftool.extended.enable = lib.mkDefault virtCfg.ovftool.enable;
        };
      };
    };
}
