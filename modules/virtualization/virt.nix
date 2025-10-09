{ config, lib, ... }:
let
  virtualizationNamespace = lib.attrByPath [ "virtualization" ] { } config.flake.nixosModules;
  featureNames = [
    "docker"
    "libvirt"
    "virtualbox"
    "vmware"
  ];

  getModule =
    name:
    let
      path = [ name ];
    in
    if lib.hasAttrByPath path virtualizationNamespace then
      lib.getAttrFromPath path virtualizationNamespace
    else
      throw ("Unknown virtualization feature '" + name + "' referenced by virt module");

  virtModule =
    { config, lib, ... }:
    let
      cfg = config.virt or { };
      isEnabled = name: lib.attrByPath [ name "enable" ] false cfg;
      activeFeatures = lib.filter isEnabled featureNames;
      featureImports = map getModule activeFeatures;
      hmAppsForFeature =
        feature:
        if feature == "docker" then
          [ "lazydocker" ]
        else if feature == "libvirt" then
          [ "virt-manager" ]
        else
          [ ];
      hmApps = lib.flatten (map hmAppsForFeature activeFeatures);
    in
    {
      options.virt =
        let
          mkFeatureOption = name: lib.mkEnableOption ("Enable " + name + " virtualization stack");
        in
        {
          docker.enable = mkFeatureOption "Docker";
          libvirt.enable = mkFeatureOption "libvirt";
          virtualbox.enable = mkFeatureOption "VirtualBox";
          vmware.enable = mkFeatureOption "VMware Workstation";
        };

      imports = featureImports;

      config = lib.mkMerge [
        (lib.mkIf (hmApps != [ ]) {
          home-manager.extraAppImports = lib.mkAfter hmApps;
        })
      ];
    };
in
{
  flake.nixosModules.virtualization.virt = virtModule;
  flake.nixosModules.virt = virtModule;
}
