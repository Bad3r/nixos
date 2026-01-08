_: {
  configurations.nixos.system76.module =
    {
      config,
      lib,
      ...
    }:
    let
      virtCfg = config.system76.virtualization;
    in
    {
      options.system76.virtualization = {
        libvirt.enable = lib.mkEnableOption "Enable libvirt tooling on the System76 host" // {
          default = false;
        };
        vmware.enable = lib.mkEnableOption "Enable VMware Workstation on the System76 host";
        ovftool.enable = lib.mkEnableOption "Install VMware OVF Tool" // {
          default = false;
        };
      };

      config = {
        # TODO(#41): Re-enable when readline70 builds with GCC 15
        # See: https://bugzilla.redhat.com/show_bug.cgi?id=2347347
        system76.virtualization.vmware.enable = lib.mkDefault false;
        system76.virtualization.ovftool.enable = lib.mkDefault false;

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
