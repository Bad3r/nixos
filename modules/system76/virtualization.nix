{ config, lib, ... }:
let
  virtualizationNamespace = lib.attrByPath [ "virtualization" ] { } (
    (config.flake or { }).nixosModules or { }
  );
  libvirtModule = lib.attrByPath [ "libvirt" ] null virtualizationNamespace;
  vmwareModule = lib.attrByPath [ "vmware" ] null virtualizationNamespace;
  moduleImports = lib.filter (m: m != null) [
    libvirtModule
    vmwareModule
  ];
in
{
  configurations.nixos.system76.module =
    { ... }:
    {
      imports = moduleImports;
    };
}
