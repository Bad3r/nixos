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
      message =
        "system76 moduleNamespace "
        + name
        + ": "
        + (if direct then "direct " else "")
        + (if content then "content " else "")
        + (if nestedBase then "nested " else "");
    in
    builtins.trace message (direct || content || nestedBase);
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
      message =
        "system76 nixos modules keys: "
        + (if value != { } then builtins.concatStringsSep ", " (builtins.attrNames value) else "<empty>");
    in
    builtins.trace message value;
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
      keysMessage =
        "system76 hmModulesFromConfig keys: "
        + (if value == { } then "<empty>" else builtins.concatStringsSep ", " (builtins.attrNames value));
      baseMessage =
        "system76 hm config has base: "
        + (if value != { } && moduleNamespace value "base" then "yes" else "no");
    in
    builtins.trace baseMessage (builtins.trace keysMessage value);
  homeManagerModulesFromSelf =
    if selfFlake != null then (selfFlake.homeManagerModules or { }) else { };
  mergedHomeManagerModules =
    fallbackHomeManagerModules // homeManagerModulesFromSelf // homeManagerModulesFromConfig;
  homeManagerModules =
    let
      keys =
        if mergedHomeManagerModules == { } then
          "<empty>"
        else
          builtins.concatStringsSep ", " (builtins.attrNames mergedHomeManagerModules);
      keysMessage = "system76 hm modules keys: " + keys;
      finalMessage = "system76 hm keys before returning module: " + keys;
    in
    builtins.trace finalMessage (builtins.trace keysMessage mergedHomeManagerModules);
  hasModule = name: lib.hasAttr name nixosModules;
  getModule =
    name:
    let
      hmKeys =
        if homeManagerModules == { } then
          "<empty>"
        else
          builtins.concatStringsSep ", " (builtins.attrNames homeManagerModules);
      messagePrefix = "system76 getModule(" + name + ") hm keys: " + hmKeys + " -> ";
    in
    if hasModule name then
      builtins.trace (messagePrefix + "hit") (lib.getAttr name nixosModules)
    else
      builtins.trace (messagePrefix + "miss") null;
  roleHelpers =
    (config.flake.lib.nixos.roles or { }) // (config._module.args.nixosRoleHelpers or { });
  getRoleModule =
    name:
    let
      getRole = roleHelpers.getRole or (_: null);
      roleValue = getRole name;
      hmKeys =
        if homeManagerModules == { } then
          "<empty>"
        else
          builtins.concatStringsSep ", " (builtins.attrNames homeManagerModules);
    in
    if roleValue != null then
      builtins.trace ("system76 getRoleModule(" + name + ") hm keys: " + hmKeys + " -> helper") roleValue
    else if lib.hasAttrByPath [ "roles" name ] nixosModules then
      builtins.trace ("system76 getRoleModule(" + name + ") hm keys: " + hmKeys + " -> flake") (
        lib.getAttrFromPath [ "roles" name ] nixosModules
      )
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
    builtins.trace ("system76 baseModule present: " + (if value == null then "no" else "yes")) value;
  flakeInitModule = _: {
    flake = lib.mkDefault { };
  };
  traceModule =
    name: module:
    builtins.trace (
      "system76 baseModules includes " + name + ": " + (if module == null then "null" else "set")
    ) module;
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
    (traceModule "base" baseModule)
    bundleFlagModule
    (traceModule "inputs.hw.system76" inputs.nixos-hardware.nixosModules.system76)
    (traceModule "inputs.hw.system76-darp6" inputs.nixos-hardware.nixosModules.system76-darp6)
    (traceModule "workstation" workstationModule)
    (traceModule "system76-support" (getModule "system76-support"))
    (traceModule "hardware-lenovo-y27q-20" (getModule "hardware-lenovo-y27q-20"))
    (traceModule "duplicati-r2" (getModule "duplicati-r2"))
    (traceModule "virt" (getModule "virt"))
  ];
  baseModules = builtins.trace (
    "system76 hm keys after baseModules: "
    + (
      if homeManagerModules == { } then
        "<empty>"
      else
        builtins.concatStringsSep ", " (builtins.attrNames homeManagerModules)
    )
  ) (lib.filter (module: module != null) baseModulesRaw);
  virtualizationModules = lib.filter (module: module != null) (
    map
      (
        name:
        let
          module = getVirtualizationModule name;
        in
        builtins.trace (
          "system76 getVirtualizationModule(" + name + ") -> " + (if module == null then "null" else "set")
        ) module
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
