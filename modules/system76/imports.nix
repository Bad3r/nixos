{
  config,
  lib,
  inputs,
  ...
}:
let
  flake = config.flake or { };
  selfFlake = config._module.args.self or inputs.self or null;
  moduleNamespace =
    attrs: name:
    let
      direct = lib.hasAttr name attrs;
      content = lib.hasAttrByPath [ "content" name ] attrs;
      nestedBase =
        lib.hasAttrByPath [ "content" "content" name ] attrs
        && lib.hasAttrByPath [ "content" name "imports" ] attrs.content;
    in
    direct || content || nestedBase;
  flakeNixosModulesBootstrap = import ./flake-nixosModules-bootstrap.nix;
  fallbackEval = lib.evalModules {
    modules = [
      flakeNixosModulesBootstrap
      (import ./../meta/flake-output.nix)
      (import ./../meta/nixos-home-manager-collect.nix)
      (import ./../meta/nixos-role-helpers.nix)
      (import ./../meta/nixos-app-helpers.nix)
    ];
    specialArgs = {
      inherit lib inputs flake;
      self = if selfFlake != null then selfFlake else { };
      system76NeedsFlakeBootstrap = true;
    };
  };
  fallbackNixosModules = fallbackEval.config.flake.nixosModules or { };
  fallbackHomeManagerModules = fallbackEval.config.flake.homeManagerModules or { };
  nixosModulesFromConfig =
    let
      value = flake.nixosModules or { };
    in
    value;
  nixosModulesFromSelf = if selfFlake != null then (selfFlake.nixosModules or { }) else { };
  nixosModules =
    if nixosModulesFromConfig != { } && moduleNamespace nixosModulesFromConfig "base" then
      nixosModulesFromConfig
    else if nixosModulesFromSelf != { } && moduleNamespace nixosModulesFromSelf "base" then
      nixosModulesFromSelf
    else
      fallbackNixosModules;
  homeManagerModulesFromConfig =
    let
      value = flake.homeManagerModules or { };
    in
    value;
  homeManagerModulesFromSelf =
    if selfFlake != null then (selfFlake.homeManagerModules or { }) else { };
  mergedHomeManagerModules =
    fallbackHomeManagerModules // homeManagerModulesFromSelf // homeManagerModulesFromConfig;
  hasModule = name: lib.hasAttr name nixosModules;
  getModule = name: if hasModule name then lib.getAttr name nixosModules else null;
  roleHelpers =
    (config.flake.lib.nixos.roles or { }) // (config._module.args.nixosRoleHelpers or { });
  getRoleModule =
    name:
    let
      getRole = roleHelpers.getRole or (_: null);
      roleValue = getRole name;
    in
    if roleValue != null then
      roleValue
    else if lib.hasAttrByPath [ "roles" name ] nixosModules then
      lib.getAttrFromPath [ "roles" name ] nixosModules
    else
      throw (
        "system76 host requires role " + name + " but it was not found in helpers or flake.nixosModules"
      );
  roleModules = map getRoleModule roleNames;
  baseRoleModule = getRoleModule "base";
  baseRoleAppModules =
    let
      imports = baseRoleModule.imports or [ ];
      tail = if imports == [ ] then [ ] else lib.drop 1 imports;
    in
    lib.filter (module: module != null) tail;
  getVirtualizationModule =
    name:
    if lib.hasAttrByPath [ "virtualization" name ] nixosModules then
      lib.getAttrFromPath [ "virtualization" name ] nixosModules
    else
      null;
  roleNames = [
    "desktop"
    "files"
    "warp-client"
    "pentesting-devshell"
    "chat"
  ];
  workstationModule = getModule "workstation";
  baseModule =
    let
      value = getModule "base";
    in
    value;
  flakeInitModule = _: {
    flake = lib.mkDefault { };
  };
  bundleFlagModule =
    {
      lib,
      ...
    }:
    {
      _module.args.homeManagerBundleInjected = lib.mkDefault true;
    };
  baseModulesRaw = [
    flakeNixosModulesBootstrap
    flakeInitModule
    baseModule
    bundleFlagModule
    inputs.nixos-hardware.nixosModules.system76
    inputs.nixos-hardware.nixosModules.system76-darp6
    workstationModule
    (getModule "system76-support")
    (getModule "hardware-lenovo-y27q-20")
    (getModule "duplicati-r2")
    (getModule "virt")
  ];
  baseModules = lib.filter (module: module != null) baseModulesRaw;
  virtualizationModules = lib.filter (module: module != null) (
    map
      (
        name:
        let
          module = getVirtualizationModule name;
        in
        module
      )
      [
        "docker"
        "libvirt"
        "ovftool"
        "vmware"
      ]
  );
  selfRevision =
    let
      self = inputs.self or null;
    in
    if self != null then
      let
        dirty = self.dirtyRev or null;
        rev = self.rev or null;
      in
      if dirty != null then dirty else rev
    else
      null;
in
{
  configurations.nixos.system76.module = {
    _module = {
      check = true;
      args = {
        inputs = lib.mkDefault inputs;
        self = lib.mkDefault (inputs.self or null);
      };
    };
    flake.homeManagerModules = mergedHomeManagerModules;
    imports =
      baseModules
      ++ baseRoleAppModules
      ++ virtualizationModules
      ++ roleModules
      ++ lib.optional (hasModule "ssh") nixosModules.ssh;

    nixpkgs.allowedUnfreePackages = lib.mkAfter [
      "p7zip-rar"
      "rar"
      "unrar"
    ];
  };

  # Export the System76 configuration so the flake exposes it under nixosConfigurations
  flake = lib.mkIf (lib.hasAttrByPath [ "configurations" "nixos" "system76" "module" ] config) {
    nixosConfigurations.system76 = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        (
          { lib, ... }:
          lib.mkIf (selfRevision != null) {
            system.configurationRevision = lib.mkDefault selfRevision;
          }
        )
        config.configurations.nixos.system76.module
      ];
      specialArgs = {
        inherit inputs;
        self = inputs.self or null;
        system76NeedsFlakeBootstrap = true;
        homeManagerBundleInjected = false;
      };
    };
  };
}
