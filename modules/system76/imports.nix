{
  config,
  lib,
  inputs,
  ...
}:
let
  flake = if config ? flake then config.flake else { };
  selfFlake = config._module.args.self or inputs.self or null;
  moduleNamespace =
    attrs: name:
    let
      direct = lib.hasAttr name attrs;
      content = lib.hasAttrByPath [ "content" name ] attrs;
      nestedBase =
        lib.hasAttrByPath [ "content" "content" name ] attrs
        && lib.hasAttrByPath [ "content" name "imports" ] attrs.content;
      _ = builtins.trace (
        "system76 moduleNamespace "
        + name
        + ": "
        + (if direct then "direct " else "")
        + (if content then "content " else "")
        + (if nestedBase then "nested " else "")
      ) null;
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
      inherit lib inputs;
      flake = flake;
      self = if selfFlake != null then selfFlake else { };
      system76NeedsFlakeBootstrap = true;
    };
  };
  fallbackNixosModules = fallbackEval.config.flake.nixosModules or { };
  fallbackHomeManagerModules = fallbackEval.config.flake.homeManagerModules or { };
  nixosModulesFromConfig = flake.nixosModules or { };
  nixosModulesFromSelf = if selfFlake != null then (selfFlake.nixosModules or { }) else { };
  nixosModules =
    if nixosModulesFromConfig != { } && moduleNamespace nixosModulesFromConfig "base" then
      nixosModulesFromConfig
    else if nixosModulesFromSelf != { } && moduleNamespace nixosModulesFromSelf "base" then
      nixosModulesFromSelf
    else
      fallbackNixosModules;
  _nixosTrace = builtins.trace (
    "system76 nixos modules keys: "
    + (
      if nixosModulesFromConfig != { } then
        builtins.concatStringsSep ", " (builtins.attrNames nixosModulesFromConfig)
      else
        "<empty>"
    )
  ) null;
  homeManagerModulesFromConfig = flake.homeManagerModules or { };
  homeManagerModulesFromSelf =
    if selfFlake != null then (selfFlake.homeManagerModules or { }) else { };
  _hmConfigTypeTrace = builtins.trace (
    "system76 hmModulesFromConfig keys: "
    + (
      if homeManagerModulesFromConfig == { } then
        "<empty>"
      else
        builtins.concatStringsSep ", " (builtins.attrNames homeManagerModulesFromConfig)
    )
  ) null;
  _hmConfigTrace = builtins.trace (
    "system76 hm config has base: "
    + (
      if homeManagerModulesFromConfig != { } && moduleNamespace homeManagerModulesFromConfig "base" then
        "yes"
      else
        "no"
    )
  ) null;
  homeManagerModules =
    if homeManagerModulesFromConfig != { } && moduleNamespace homeManagerModulesFromConfig "base" then
      homeManagerModulesFromConfig
    else if homeManagerModulesFromSelf != { } && moduleNamespace homeManagerModulesFromSelf "base" then
      homeManagerModulesFromSelf
    else
      fallbackHomeManagerModules;
  _hmTrace = builtins.trace (
    "system76 hm modules keys: "
    + (
      if homeManagerModules == { } then
        "<empty>"
      else
        builtins.concatStringsSep ", " (builtins.attrNames homeManagerModules)
    )
  ) null;
  _hmFinalTrace = builtins.trace (
    "system76 hm keys before returning module: "
    + (
      if homeManagerModules == { } then
        "<empty>"
      else
        builtins.concatStringsSep ", " (builtins.attrNames homeManagerModules)
    )
  ) null;
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
  baseModule = getModule "base";
  _baseTrace = builtins.trace (
    "system76 baseModule present: " + (if baseModule == null then "no" else "yes")
  ) null;
  flakeInitModule = _: {
    flake = lib.mkDefault { };
  };
  traceModule =
    name: module:
    builtins.trace (
      "system76 baseModules includes " + name + ": " + (if module == null then "null" else "set")
    ) module;
  baseModulesRaw = [
    flakeNixosModulesBootstrap
    flakeInitModule
    (traceModule "base" baseModule)
    (traceModule "inputs.hw.system76" inputs.nixos-hardware.nixosModules.system76)
    (traceModule "inputs.hw.system76-darp6" inputs.nixos-hardware.nixosModules.system76-darp6)
    (traceModule "packages" (getModule "packages"))
    (traceModule "workstation" workstationModule)
    (traceModule "system76-support" (getModule "system76-support"))
    (traceModule "security" (getModule "security"))
    (traceModule "hardware-lenovo-y27q-20" (getModule "hardware-lenovo-y27q-20"))
    (traceModule "duplicati-r2" (getModule "duplicati-r2"))
    (traceModule "virt" (getModule "virt"))
  ];
  baseModules = lib.filter (module: module != null) baseModulesRaw;
  _hmAfterBase = builtins.trace (
    "system76 hm keys after baseModules: "
    + (
      if homeManagerModules == { } then
        "<empty>"
      else
        builtins.concatStringsSep ", " (builtins.attrNames homeManagerModules)
    )
  ) null;
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
    _module.check = true;
    _module.args.inputs = lib.mkDefault inputs;
    _module.args.self = lib.mkDefault (inputs.self or null);
    flake.homeManagerModules =
      let
        configHasBase =
          homeManagerModulesFromConfig != { } && moduleNamespace homeManagerModulesFromConfig "base";
      in
      lib.mkIf (!configHasBase) (
        lib.mkMerge [
          fallbackHomeManagerModules
        ]
      );
    imports =
      baseModules
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
      };
    };
  };
}
