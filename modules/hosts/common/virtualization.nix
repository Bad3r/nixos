_:
let
  body =
    {
      config,
      lib,
      ...
    }:
    let
      virtCfg = config.host.virtualization;
    in
    {
      options.host.virtualization = {
        libvirt.enable = lib.mkEnableOption "Enable libvirt tooling on this host" // {
          default = false;
        };
        vmware.enable = lib.mkEnableOption "Enable VMware Workstation on this host";
        ovftool.enable = lib.mkEnableOption "Install VMware OVF Tool" // {
          default = false;
        };
      };

      config = {
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
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
