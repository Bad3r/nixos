# statix:ignore-file
{
  flake ? builtins.getFlake (toString ./.),
  lib ? flake.inputs.nixpkgs.lib,
}:
let
  inherit (flake.nixosConfigurations.system76) _module;
  sourceModulesResult = builtins.tryEval _module.args.modules;
  sourceModules = if sourceModulesResult.success then sourceModulesResult.value else [ ];
  sourceModulesWithBootstrap = [ flakePartsBootstrapModule ] ++ sourceModules;
  freeform = lib.types.attrsOf lib.types.anything;
  roleDir = ./../modules/roles;
  appsDir = ./../modules/apps;
  langDir = ./../modules/languages;
  windowManagerDir = ./../modules/window-manager;
  rolesDir = ./../modules/roles;
  flakePartsModulePath = flake.inputs.flake-parts.outPath + "/modules/nixosModules.nix";
  flakePartsBootstrapModule = (import flakePartsModulePath) {
    inherit (flake.inputs.nixpkgs) lib;
    self = flake;
    flake-parts-lib = flake.inputs.flake-parts.lib;
    moduleLocation = flakePartsModulePath;
  };
  roleNames =
    let
      entries = builtins.readDir roleDir;
      names = builtins.filter (name: entries.${name} == "regular" && lib.hasSuffix ".nix" name) (
        builtins.attrNames entries
      );
    in
    builtins.map (name: lib.removeSuffix ".nix" name) names;
  appNames =
    let
      entries = builtins.readDir appsDir;
      files = builtins.filter (name: entries.${name} == "regular" && lib.hasSuffix ".nix" name) (
        builtins.attrNames entries
      );
    in
    builtins.map (name: lib.removeSuffix ".nix" name) files;
  langNames =
    let
      entries = if builtins.pathExists langDir then builtins.readDir langDir else { };
      files = builtins.filter (name: entries.${name} == "regular" && lib.hasSuffix ".nix" name) (
        builtins.attrNames entries
      );
      trim =
        name:
        let
          withoutSuffix = lib.removeSuffix ".nix" name;
        in
        if lib.hasPrefix "lang-" withoutSuffix then
          builtins.substring 5 (builtins.stringLength withoutSuffix - 5) withoutSuffix
        else
          withoutSuffix;
    in
    builtins.map trim files;
  windowManagerNames =
    let
      entries = builtins.readDir windowManagerDir;
      files = builtins.filter (name: entries.${name} == "regular" && lib.hasSuffix ".nix" name) (
        builtins.attrNames entries
      );
    in
    builtins.map (name: lib.removeSuffix ".nix" name) files;

  mkExportOrStub =
    filePath: path:
    let
      imported = import filePath;
    in
    if builtins.isAttrs imported && lib.hasAttrByPath path imported then
      lib.getAttrFromPath path imported
    else
      (_: { });

  mkAppStub =
    name:
    mkExportOrStub (appsDir + "/${name}.nix") [
      "flake"
      "nixosModules"
      "apps"
      name
    ];

  appStubs = lib.genAttrs appNames mkAppStub;

  mkLangStub =
    name:
    mkExportOrStub (langDir + "/lang-${name}.nix") [
      "flake"
      "nixosModules"
      "lang"
      name
    ];

  langStubs = lib.genAttrs langNames mkLangStub;

  mkWindowManagerStub =
    name:
    mkExportOrStub (windowManagerDir + "/${name}.nix") [
      "flake"
      "nixosModules"
      "window-manager"
      name
    ];

  windowManagerStubs = lib.genAttrs windowManagerNames mkWindowManagerStub;

  roleEntries = builtins.readDir rolesDir;
  roleNamesFromFiles = builtins.filter (
    name: roleEntries.${name} == "regular" && lib.hasSuffix ".nix" name
  ) (builtins.attrNames roleEntries);
  roleStubs = lib.genAttrs roleNamesFromFiles (
    filename:
    let
      name = lib.removeSuffix ".nix" filename;
    in
    {
      _file = "stub.roles.${name}";
      imports = [ (rolesDir + "/${filename}") ];
    }
  );

  mkNamespaceOption =
    name:
    lib.mkOption {
      type = lib.types.submodule { freeformType = freeform; };
      default = { };
      description = "${name} scaffold (debug only)";
    };

  scaffoldModule =
    { config, lib, ... }:
    let
      libStub = flake.lib or { };
      inherit (config) system;
      pkgs =
        if lib.hasAttrByPath [ "legacyPackages" system ] flake.inputs.nixpkgs then
          flake.inputs.nixpkgs.legacyPackages.${system}
        else
          import flake.inputs.nixpkgs { inherit system; };
    in
    {
      options = {
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
        systemd = mkNamespaceOption "systemd";
        users = mkNamespaceOption "users";
        hardware = mkNamespaceOption "hardware";
        networking = mkNamespaceOption "networking";
        virtualisation = mkNamespaceOption "virtualisation";
        console = mkNamespaceOption "console";
        security = mkNamespaceOption "security";
        programs = mkNamespaceOption "programs";
        nix = mkNamespaceOption "nix";
        fonts = mkNamespaceOption "fonts";
        i18n = mkNamespaceOption "i18n";
        time = mkNamespaceOption "time";
        xdg = mkNamespaceOption "xdg";
        sound = mkNamespaceOption "sound";
        documentation = mkNamespaceOption "documentation";
        home-manager = mkNamespaceOption "home-manager";
        lib = lib.mkOption {
          type = lib.types.attrs;
          default = libStub;
        };
        debug = {
          hmTrace = mkNamespaceOption "debug.hmTrace";
          argsTrace = mkNamespaceOption "debug.argsTrace";
          roleProbe = mkNamespaceOption "debug.roleProbe";
          flakeTrace = mkNamespaceOption "debug.flakeTrace";
          flakeFinal = lib.mkOption {
            type = lib.types.attrs;
            default = { };
            description = "Final flake.nixosModules snapshot (debug only)";
          };
        };
        assertions = lib.mkOption {
          type = lib.types.listOf lib.types.anything;
          default = [ ];
        };
        warnings = lib.mkOption {
          type = lib.types.listOf lib.types.anything;
          default = [ ];
        };
      };
      config._module.args.pkgs = lib.mkDefault pkgs;
    };

  mkTraceModule =
    label:
    { config, ... }:
    let
      hm = config.home-manager or { };
      names = builtins.attrNames hm;
      msg = if names == [ ] then "<empty>" else builtins.concatStringsSep ", " names;
      moduleArgs = if config ? _module && config._module ? args then config._module.args else { };
      argNames = builtins.attrNames moduleArgs;
      argMsg = if argNames == [ ] then "<empty>" else builtins.concatStringsSep ", " argNames;
      flakeModules =
        if config ? flake && config.flake ? nixosModules then
          builtins.attrNames config.flake.nixosModules
        else
          [ ];
      flakeMsg = if flakeModules == [ ] then "<empty>" else builtins.concatStringsSep ", " flakeModules;
      roleModules =
        if config ? flake && config.flake ? nixosModules && config.flake.nixosModules ? roles then
          builtins.attrNames config.flake.nixosModules.roles
        else
          [ ];
      roleMsg = if roleModules == [ ] then "<empty>" else builtins.concatStringsSep ", " roleModules;
      homeFlakeModules =
        if config ? flake && config.flake ? homeManagerModules then
          builtins.attrNames config.flake.homeManagerModules
        else
          [ ];
      homeFlakeMsg =
        if homeFlakeModules == [ ] then "<empty>" else builtins.concatStringsSep ", " homeFlakeModules;
    in
    {
      config = {
        debug = {
          hmTrace.${label} = msg;
          argsTrace.${label} = argMsg;
          flakeTrace.${label} = {
            nixosModules = flakeMsg;
            roles = roleMsg;
            homeManagerModules = homeFlakeMsg;
          };
        };
        assertions = [
          {
            assertion = config ? flake && config.flake ? nixosModules;
            message = "flake.nixosModules missing after " + label;
          }
        ];
      };
    };

  stubModule =
    { lib, self, ... }:
    {
      config.flake.nixosModules = lib.mkDefault (
        let
          selfModules = self.nixosModules or { };
        in
        selfModules
        // {
          apps = (selfModules.apps or { }) // appStubs;
          lang = (selfModules.lang or { }) // langStubs;
          "window-manager" = (selfModules."window-manager" or { }) // windowManagerStubs;
          roles = (selfModules.roles or { }) // roleStubs;
        }
      );
    };

  mkPairs =
    prefix: modules:
    lib.imap (index: module: {
      inherit module;
      label = prefix + "/" + builtins.toString index;
    }) modules;

  instrumentModule =
    prefix: module:
    if lib.isAttrs module && module ? imports then
      module
      // {
        imports = instrumentImports prefix module.imports;
      }
    else
      module;

  instrumentImports =
    prefix: modules:
    let
      normalized = map toModule modules;
    in
    lib.concatMap (
      pair:
      let
        annotated = instrumentModule pair.label pair.module;
      in
      [
        annotated
        (mkTraceModule pair.label)
      ]
    ) (mkPairs prefix normalized);

  first = builtins.elemAt sourceModulesWithBootstrap 0;
  top = builtins.elemAt sourceModulesWithBootstrap 1;
  last = builtins.elemAt sourceModulesWithBootstrap 2;
  toModule =
    module:
    if builtins.isFunction module then
      module
    else if builtins.isAttrs module then
      if module ? _type && module._type == "order" then
        toModule module.content
      else
        module
        // {
          config = module.config or { };
          options = module.options or { };
          disabledModules = module.disabledModules or [ ];
        }
    else
      {
        _file = builtins.toString module;
        imports = [ module ];
        config = { };
        options = { };
        disabledModules = [ ];
      };
  topModule = toModule top;
  firstModule = toModule first;
  lastModule = toModule last;

  roleProbeModule =
    { config, lib, ... }:
    let
      finalFlake =
        if config ? flake && config.flake ? nixosModules then
          let
            modulesAttr = config.flake.nixosModules;
            rolesAttr =
              modulesAttr.roles or (
                if modulesAttr ? content && modulesAttr.content ? roles then modulesAttr.content.roles else { }
              );
            toNames = attr: if attr ? content then builtins.attrNames attr.content else builtins.attrNames attr;
            homeAttr = config.flake.homeManagerModules or { };
          in
          {
            nixosModules =
              if modulesAttr ? content then
                builtins.attrNames modulesAttr.content
              else
                builtins.attrNames modulesAttr;
            roles = toNames rolesAttr;
            homeManagerModules = builtins.attrNames homeAttr;
          }
        else
          {
            nixosModules = [ ];
            roles = [ ];
            homeManagerModules = [ ];
          };
      evalRole =
        name:
        let
          roleExpr = import (roleDir + "/${name}.nix");
          attempt =
            if builtins.typeOf roleExpr == "lambda" then
              builtins.tryEval (roleExpr {
                inherit config lib;
              })
            else
              builtins.tryEval roleExpr;
          rolePath = [
            "flake"
            "nixosModules"
            "roles"
            name
          ];
        in
        if attempt.success then
          let
            result = attempt.value;
            rolePresent = if builtins.isAttrs result then lib.hasAttrByPath rolePath result else false;
            payload = if rolePresent then lib.getAttrFromPath rolePath result else null;
            payloadType = if payload == null then "none" else builtins.typeOf payload;
            payloadEval =
              if payloadType == "set" && builtins.isAttrs payload then
                if payload ? imports then builtins.tryEval payload.imports else builtins.tryEval payload
              else
                {
                  success = true;
                  value = null;
                };
            resolvedKeys =
              if payloadType == "set" then
                builtins.attrNames payload
              else if builtins.isAttrs result then
                builtins.attrNames result
              else
                [ ];
          in
          {
            success = true;
            hasRoleAttr = rolePresent;
            inherit payloadType;
            keys = resolvedKeys;
            payloadEvalSuccess = payloadEval.success;
            payloadEvalError = if payloadEval.success then null else payloadEval.value;
          }
        else
          {
            success = false;
            error = attempt.value;
          };
    in
    {
      config = {
        debug = {
          roleProbe = lib.genAttrs roleNames evalRole;
          flakeFinal = finalFlake;
        };
      };
    };

  inherit (top) imports;

  interleaved = instrumentImports "system76" imports;

  baseImportsNormalized = map toModule (flake.nixosModules.base.imports or [ ]);

  baseInterleaved = instrumentImports "base" baseImportsNormalized;

  baseModule = {
    _file = "scaffold/baseModule";
    imports = baseInterleaved;
    config = { };
  };
  baseModulesForTrace = [
    scaffoldModule
    firstModule
    stubModule
    baseModule
    roleProbeModule
  ];
  modules = [
    scaffoldModule
    stubModule
    firstModule
    (mkTraceModule "pre-system76")
    (topModule // { imports = interleaved; })
    lastModule
    roleProbeModule
  ];
  specialArgs = _module.specialArgs // {
    inherit (flake) inputs;
    self = flake;
    system76NeedsFlakeBootstrap = true;
    "flake-parts-lib" = flake.inputs.flake-parts.lib;
    moduleLocation = flakePartsModulePath;
  };
  prefixHomeManagerTraces =
    let
      count = lib.length interleaved;
      limit = if count < 16 then count else 16;
      basePrefix = [
        scaffoldModule
        stubModule
        firstModule
      ];
      moduleLabel =
        module:
        if lib.isAttrs module && module ? label then
          module.label
        else if lib.isAttrs module && module ? _file then
          module._file
        else if builtins.isFunction module then
          "<lambda>"
        else
          toString module;
      evaluate =
        n:
        let
          takeAttempt = builtins.tryEval (lib.take n interleaved);
          prefix = if takeAttempt.success then basePrefix ++ takeAttempt.value else basePrefix;
          evalAttempt =
            if takeAttempt.success then
              builtins.tryEval (
                lib.evalModules {
                  modules = prefix;
                  specialArgs = specialArgs;
                }
              )
            else
              {
                success = false;
                value = takeAttempt.value;
              };
        in
        {
          step = n;
          importLabel =
            if takeAttempt.success then
              moduleLabel (builtins.elemAt takeAttempt.value (n - 1))
            else
              "<take failure>";
          success = takeAttempt.success && evalAttempt.success;
          hmKeys =
            if takeAttempt.success && evalAttempt.success then
              builtins.attrNames (evalAttempt.value.config.flake.homeManagerModules or { })
            else
              [ ];
          error =
            if !takeAttempt.success then
              builtins.toString takeAttempt.value
            else if !evalAttempt.success then
              builtins.toString evalAttempt.value
            else
              null;
        };
    in
    lib.genList (index: evaluate (index + 1)) limit;
in
{
  inherit
    modules
    specialArgs
    baseModule
    baseModulesForTrace
    scaffoldModule
    stubModule
    flakePartsBootstrapModule
    toModule
    roleProbeModule
    firstModule
    topModule
    lastModule
    sourceModules
    interleaved
    first
    top
    last
    ;
  inherit
    appNames
    langNames
    windowManagerNames
    ;
  inherit baseImportsNormalized sourceModulesWithBootstrap prefixHomeManagerTraces;
  sourceModulesError = if sourceModulesResult.success then null else sourceModulesResult.value;
  sourceModulesSuccess = sourceModulesResult.success;
}
