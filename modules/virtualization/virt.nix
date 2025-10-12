_:
let
  virtModule =
    { lib, ... }:
    let
      mkFeatureOption = name: lib.mkEnableOption ("Enable " + name + " virtualization stack");
    in
    {
      options.virt = {
        docker.enable = mkFeatureOption "Docker";
        libvirt.enable = mkFeatureOption "libvirt";
        virtualbox.enable = mkFeatureOption "VirtualBox";
        vmware.enable = mkFeatureOption "VMware Workstation";
        ovftool.enable = mkFeatureOption "VMware OVF Tool";
      };
    };
in
{
  flake.nixosModules.virtualization.virt = virtModule;
  flake.nixosModules.virt = virtModule;
}
