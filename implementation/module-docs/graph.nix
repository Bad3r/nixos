{
  flakeRoot ? ./.,
  system ? "x86_64-linux",
  flakeOverride ? null,
  pkgsOverride ? null,
  libOverride ? null,
  extraSpecialArgs ? { },
}:
let
  flakeRaw = if flakeOverride != null then flakeOverride else builtins.getFlake (toString flakeRoot);
  flakeInputsRaw = flakeRaw.inputs or { };
  fallbackInputs = {
    impermanence = {
      nixosModules = {
        impermanence = (_: { });
      };
    };
  };
  effectiveInputs = fallbackInputs // flakeInputsRaw;
  flake = flakeRaw // {
    inputs = effectiveInputs;
  };
  legacyPackages = flake.legacyPackages or { };
  legacySystems = builtins.attrNames legacyPackages;
  availableSystems = if legacySystems != [ ] then legacySystems else [ system ];
  selectedSystem =
    if builtins.elem system availableSystems then system else builtins.head availableSystems;

  fallbackPkgs =
    if pkgsOverride != null then
      pkgsOverride
    else
      import flake.inputs.nixpkgs { system = selectedSystem; };

  pinnedPkgs =
    if legacyPackages != { } && builtins.hasAttr selectedSystem legacyPackages then
      builtins.getAttr selectedSystem legacyPackages
    else
      fallbackPkgs;

  effectiveLib =
    if libOverride != null then
      libOverride
    else if pinnedPkgs ? lib then
      pinnedPkgs.lib
    else
      fallbackPkgs.lib;

  pkgsFor =
    systemName:
    if legacyPackages != { } && builtins.hasAttr systemName legacyPackages then
      builtins.getAttr systemName legacyPackages
    else
      import flake.inputs.nixpkgs { system = systemName; };

  defaultWithSystem =
    systemName: f:
    let
      pkgsForSystem = pkgsFor systemName;
    in
    f {
      inherit systemName;
      pkgs = pkgsForSystem;
      config = { };
      self = flake;
    };

  docLib = import ./lib { lib = effectiveLib; };
  lib = effectiveLib;

  filterAttrs =
    if lib ? filterAttrs then
      lib.filterAttrs
    else if lib ? attrsets && lib.attrsets ? filterAttrs then
      lib.attrsets.filterAttrs
    else
      builtins.throw "module-docs: filterAttrs missing from lib";

  stringifyError =
    value:
    let
      t = builtins.typeOf value;
    in
    if t == "string" then
      value
    else if t == "path" then
      toString value
    else if t == "int" || t == "float" || t == "bool" then
      toString value
    else if t == "list" then
      "list(" + toString (builtins.length value) + ")"
    else if t == "set" then
      "set{" + lib.concatStringsSep "," (builtins.attrNames value) + "}"
    else if t == "lambda" then
      "<function>"
    else
      "<" + t + ">";

  flakeOutPath = flake.outPath;
  flakePartsLib = if effectiveInputs ? flake-parts then effectiveInputs.flake-parts.lib else null;
  flakePartsModules =
    if
      effectiveInputs ? flake-parts
      && effectiveInputs.flake-parts ? flakeModules
      && effectiveInputs.flake-parts.flakeModules ? default
    then
      [ effectiveInputs.flake-parts.flakeModules.default ]
    else
      [ ];

  inherit (lib) types;

  moduleBase =
    let
      ownerMeta =
        if flake ? lib && flake.lib ? meta && flake.lib.meta ? owner then flake.lib.meta.owner else { };
      defaultOwnerUsername = if ownerMeta ? username then ownerMeta.username else "owner";
    in
    {
      options = {
        flake = lib.mkOption {
          type = types.submodule { freeformType = types.attrsOf types.anything; };
          default = { };
        };
        systems = lib.mkOption {
          type = types.listOf types.str;
          default = availableSystems;
        };
        inputs = lib.mkOption {
          type = types.attrsOf types.anything;
          default = { };
        };
        nixpkgs = lib.mkOption {
          type = types.submodule { freeformType = types.attrsOf types.anything; };
          default = { };
        };
        rootPath = lib.mkOption {
          type = types.str;
          default = flakeOutPath;
        };
        docExtraction = lib.mkOption {
          type = types.submodule {
            options = {
              skip = lib.mkOption {
                type = types.bool;
                default = false;
                description = "Skip module extraction when true.";
              };
              skipReason = lib.mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Explain why this module should be skipped in docs.";
              };
              tags = lib.mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "Custom tags associated with module extraction diagnostics.";
              };
            };
          };
          default = { };
        };
      };

      config = {
        systems = availableSystems;
        flake = flake // {
          inherit lib;
          meta = (flake.lib.meta or { }) // {
            owner = ownerMeta // {
              username = defaultOwnerUsername;
            };
          };
        };
        inputs = effectiveInputs;
        nixpkgs = { };
        rootPath = flakeOutPath;
        _module.args = filterAttrs (_: value: value != null) {
          pinnedPkgs = pinnedPkgs;
          inherit flakeOutPath flake;
          inputs = effectiveInputs;
          withSystem = defaultWithSystem;
          flake-parts-lib = flakePartsLib;
        };
        _module.check = false;
      };
    };

  specialArgs = filterAttrs (_: value: value != null) (
    {
      inherit lib flake;
      pkgs = pinnedPkgs;
      inputs = effectiveInputs;
      rootPath = flakeOutPath;
      withSystem = defaultWithSystem;
    }
    // extraSpecialArgs
  );

  normalizeModule = value: if builtins.isFunction value then value else (_: value);

  relativePath =
    path:
    if path == null then
      null
    else
      let
        asString = toString path;
        prefix = "${toString flakeRoot}/";
      in
      if lib.hasPrefix prefix asString then lib.removePrefix prefix asString else asString;

  getAttrSource =
    attrset: name:
    let
      pos = builtins.unsafeGetAttrPos name attrset;
    in
    if pos ? file && pos.file != "" then relativePath pos.file else null;

  aggregatorAllowedKeys = [
    "imports"
    "_file"
    "attrPath"
  ];

  isAggregator =
    value:
    let
      attempt = builtins.tryEval (
        builtins.isAttrs value
        && value ? imports
        && (
          let
            importsAttempt = builtins.tryEval value.imports;
          in
          importsAttempt.success && builtins.isList importsAttempt.value
        )
        && lib.all (key: lib.elem key aggregatorAllowedKeys) (builtins.attrNames value)
      );
    in
    attempt.success && attempt.value;

  collectModules =
    let
      recBind = rec {
        importsFor =
          value:
          let
            attempt = builtins.tryEval (
              if builtins.isAttrs value && value ? imports then value.imports else [ ]
            );
          in
          if attempt.success && builtins.isList attempt.value then attempt.value else [ ];

        collectValue =
          value: path: source:
          let
            nextSource = if builtins.isAttrs value && value ? _file then relativePath value._file else source;
          in
          if isAggregator value then
            lib.concatLists (map (entry: collectImportEntry entry path nextSource) (importsFor value))
          else if builtins.isFunction value then
            [
              {
                keyPath = path;
                module = value;
                sourcePath = source;
              }
            ]
          else if builtins.isAttrs value then
            [
              {
                keyPath = path;
                module = normalizeModule value;
                sourcePath = nextSource;
              }
            ]
          else
            [ ];

        collectImportEntry =
          entry: path: source:
          let
            entrySource = if entry ? _file then relativePath entry._file else source;
            inner = importsFor entry;
          in
          lib.concatLists (
            map (
              child:
              if isAggregator child then
                collectValue child path entrySource
              else if builtins.isAttrs child then
                lib.concatLists (
                  lib.mapAttrsToList (name: value: collectValue value (path ++ [ name ]) entrySource) child
                )
              else
                [ ]
            ) inner
          );
      };
    in
    recBind.collectValue;

  collectEntriesFor =
    modulesAttr: namespace:
    lib.concatLists (
      lib.mapAttrsToList (
        name: value: collectModules value [ name ] (getAttrSource modulesAttr name)
      ) modulesAttr
    );

  docFromEvaluation =
    {
      namespace,
      attrPath,
      sourcePath,
      evaluation,
    }:
    let
      meta = evaluation.config.meta or { };
      docExtractionCfg = evaluation.config.docExtraction or { };
      skipReason = docExtractionCfg.skipReason or null;
      skipFlag = docExtractionCfg.skip or (skipReason != null);
      base = docLib.moduleDocFromEvaluation {
        inherit
          namespace
          attrPath
          sourcePath
          evaluation
          ;
        originSystem = namespace;
        skipReason = skipReason;
        meta = meta;
      };
    in
    base
    // {
      inherit skipReason;
      skip = skipFlag;
    };

  processEntry =
    namespace: entry:
    let
      evaluationAttempt = builtins.tryEval (
        lib.evalModules {
          modules = [ moduleBase ] ++ flakePartsModules ++ [ entry.module ];
          inherit specialArgs;
        }
      );
    in
    if evaluationAttempt.success then
      let
        moduleDocAttempt = builtins.tryEval (docFromEvaluation {
          inherit namespace;
          attrPath = entry.keyPath;
          sourcePath = entry.sourcePath or "unknown";
          evaluation = evaluationAttempt.value;
        });
      in
      if moduleDocAttempt.success then
        let
          moduleDoc = moduleDocAttempt.value;
        in
        {
          namespace = namespace;
          keyPath = entry.keyPath;
          attrPath = entry.keyPath;
          sourcePath = entry.sourcePath or "unknown";
          status = if moduleDoc.skip then "skipped" else "ok";
          error = null;
          data = moduleDoc;
        }
      else
        {
          namespace = namespace;
          keyPath = entry.keyPath;
          attrPath = entry.keyPath;
          sourcePath = entry.sourcePath or "unknown";
          status = "error";
          error = "Failed to render module: ${stringifyError moduleDocAttempt.value}";
          data = null;
        }
    else
      {
        namespace = namespace;
        keyPath = entry.keyPath;
        attrPath = entry.keyPath;
        sourcePath = entry.sourcePath or "unknown";
        status = "error";
        error = "Failed to evaluate module: ${stringifyError evaluationAttempt.value}";
        data = null;
      };

  processNamespace =
    namespace: modulesAttr:
    let
      entries = collectEntriesFor modulesAttr namespace;
      processed = map (processEntry namespace) entries;
    in
    {
      modules = processed;
    };

  namespaces = {
    nixos =
      if flake ? nixosModules then processNamespace "nixos" flake.nixosModules else { modules = [ ]; };
    homeManager =
      if flake ? homeManagerModules then
        processNamespace "home-manager" flake.homeManagerModules
      else
        { modules = [ ]; };
  };

  namespaceStats = lib.mapAttrs (_: payload: docLib.summarizeModules payload.modules) namespaces;

in
{
  inherit namespaces namespaceStats;
  modules = lib.concatMap (ns: namespaces.${ns}.modules) [
    "nixos"
    "homeManager"
  ];
}
