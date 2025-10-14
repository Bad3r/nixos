_: {
  configurations.nixos.system76.module =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      virtCfg = config.system76.virtualization;
      owner = lib.attrByPath [ "flake" "lib" "meta" "owner" "username" ] null config;
    in
    {
      options.system76.virtualization = {
        libvirt.enable = lib.mkEnableOption "Enable libvirt tooling on the System76 host" // {
          default = true;
        };
        vmware.enable = lib.mkEnableOption "Enable VMware Workstation on the System76 host";
        ovftool.enable = lib.mkEnableOption "Install VMware OVF Tool" // {
          default = true;
        };
      };

      config = lib.mkMerge [
        {
          system76.virtualization.vmware.enable = lib.mkDefault true;
          system76.virtualization.ovftool.enable = lib.mkDefault true;

          virt = {
            libvirt.enable = virtCfg.libvirt.enable;
            vmware.enable = virtCfg.vmware.enable;
            ovftool.enable = virtCfg.ovftool.enable;
          };
        }
        (lib.mkIf virtCfg.libvirt.enable (
          lib.mkMerge [
            {
              virtualisation.libvirtd = {
                enable = true;
                qemu = {
                  package = pkgs.qemu_kvm;
                  runAsRoot = false;
                };
              };

              home-manager.extraAppImports = lib.mkAfter [ "virt-manager" ];
            }
            (lib.mkIf (owner != null) {
              users.users.${owner}.extraGroups = lib.mkAfter [
                "kvm"
                "libvirtd"
                "qemu-libvirtd"
              ];
            })
          ]
        ))
        (lib.mkIf virtCfg.vmware.enable {
          virtualisation.vmware.host = {
            enable = true;
            package = pkgs.vmware-workstation;
          };

          nixpkgs.allowedUnfreePackages = lib.mkAfter [
            "vmware-workstation"
          ];
        })
      ];
    };
}
