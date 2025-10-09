_: {
  configurations.nixos.system76.module =
    { config, lib, ... }:
    let
      virtualizationNamespace = lib.attrByPath [ "virtualization" ] { } (
        config.flake.nixosModules or { }
      );
      libvirtModule = lib.attrByPath [ "libvirt" ] null virtualizationNamespace;
      vmwareModule = lib.attrByPath [ "vmware" ] null virtualizationNamespace;
      moduleImports = lib.filter (m: m != null) [
        libvirtModule
        vmwareModule
      ];
    in
    {
      imports = lib.mkAfter moduleImports;
    };
}
