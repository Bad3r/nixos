# statix:ignore-file
{
  flake ? builtins.getFlake (toString ./.),
  lib ? flake.inputs.nixpkgs.lib,
}:
let
  inherit (flake.nixosConfigurations.system76) _module;
  sourceModules = _module.args.modules;
  freeform = lib.types.attrsOf lib.types.anything;

  mkNamespaceOption =
    name:
    lib.mkOption {
      type = lib.types.submodule { freeformType = freeform; };
      default = { };
      description = "${name} scaffold (debug only)";
    };

  scaffoldModule =
    { lib, ... }:
    let
      libStub = flake.lib or { };
    in
    {
      options = {
        flake = lib.mkOption {
          type = lib.types.attrs;
          default = flake;
        };
        nixpkgs = lib.mkOption {
          type = lib.types.submodule { freeformType = freeform; };
          default = flake.inputs.nixpkgs or { };
        };
        system = lib.mkOption {
          type = lib.types.str;
          default = "x86_64-linux";
        };
        boot = mkNamespaceOption "boot";
        environment = mkNamespaceOption "environment";
        services = mkNamespaceOption "services";
        users = mkNamespaceOption "users";
        hardware = mkNamespaceOption "hardware";
        networking = mkNamespaceOption "networking";
        virtualisation = mkNamespaceOption "virtualisation";
        lib = lib.mkOption {
          type = lib.types.attrs;
          default = libStub;
        };
        debug.hmTrace = mkNamespaceOption "debug.hmTrace";
        assertions = lib.mkOption {
          type = lib.types.listOf lib.types.anything;
          default = [ ];
        };
        warnings = lib.mkOption {
          type = lib.types.listOf lib.types.anything;
          default = [ ];
        };
      };
    };

  mkTraceModule =
    label:
    { config, ... }:
    let
      hm = config.home-manager or { };
      names = builtins.attrNames hm;
      msg = if names == [ ] then "<empty>" else builtins.concatStringsSep ", " names;
    in
    {
      config.debug.hmTrace.${label} = msg;
    };

  first = builtins.elemAt sourceModules 0;
  top = builtins.elemAt sourceModules 1;
  last = builtins.elemAt sourceModules 2;

  inherit (top) imports;

  pairs = lib.imap (index: module: {
    inherit module;
    label = "system76/" + builtins.toString index;
  }) imports;

  interleaved = lib.concatMap (pair: [
    pair.module
    (mkTraceModule pair.label)
  ]) pairs;

  baseTop = flake.nixosModules.base;
  baseImports = baseTop.imports;

  basePairs = lib.imap (index: module: {
    inherit module;
    label = "base/" + builtins.toString index;
  }) baseImports;

  baseInterleaved = lib.concatMap (pair: [
    pair.module
    (mkTraceModule pair.label)
  ]) basePairs;

  baseModule = baseTop // {
    imports = baseInterleaved;
  };
  baseModulesForTrace = [
    scaffoldModule
    baseModule
  ];
  modules = [
    scaffoldModule
    first
    (mkTraceModule "pre-system76")
    (top // { imports = interleaved; })
    last
  ];
  specialArgs = _module.specialArgs // {
    inherit (flake) inputs;
    self = flake;
  };
in
{
  inherit
    modules
    specialArgs
    baseModule
    baseModulesForTrace
    ;
}
