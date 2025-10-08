# Extract NixOS modules documentation data for Cloudflare Workers API
{
  flakeRoot ? ./.,
  system ? "x86_64-linux",
  pkgs ? null,
  libOverride ? null,
}:

let
  # Resolve the repo flake so we can evaluate modules the same way CI does.
  flake = builtins.getFlake (toString flakeRoot);

  legacyPackages = flake.legacyPackages or { };
  legacySystems = builtins.attrNames legacyPackages;
  availableSystems = if legacySystems != [ ] then legacySystems else [ system ];

  selectedSystem =
    if builtins.elem system availableSystems then system else builtins.head availableSystems;

  fallbackPkgs = if pkgs != null then pkgs else import <nixpkgs> { inherit system; };

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

  # Helper to obtain pkgs for an arbitrary system
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

  # Use the pinned lib/pkgs pair for all extractions
  extractLib = import (flakeRoot + /implementation/lib/extract-modules.nix) {
    lib = effectiveLib;
    pkgs = pinnedPkgs;
  };

  lib = effectiveLib;
  filterAttrs =
    if lib ? filterAttrs then
      lib.filterAttrs
    else if lib ? attrsets && lib.attrsets ? filterAttrs then
      lib.attrsets.filterAttrs
    else
      builtins.throw "extract-nixos-modules: filterAttrs missing from selected lib";
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
  flakeInputs = flake.inputs or { };
  fallbackInputs = {
    impermanence = {
      nixosModules = {
        impermanence = (_: { });
      };
    };
  };
  effectiveInputs = fallbackInputs // flakeInputs;
  flakeOutPath = flake.outPath;
  flakePartsLib = if flakeInputs ? flake-parts then flakeInputs.flake-parts.lib else null;
  flakePartsModules =
    if
      flakeInputs ? flake-parts
      && flakeInputs.flake-parts ? flakeModules
      && flakeInputs.flake-parts.flakeModules ? default
    then
      [ flakeInputs.flake-parts.flakeModules.default ]
    else
      [ ];

  inherit (lib) types;

  moduleBase =
    let
      ownerMeta =
        if flake ? lib && flake.lib ? meta && flake.lib.meta ? owner then
          flake.lib.meta.owner
        else
          { };
      defaultOwnerUsername =
        if ownerMeta ? username then ownerMeta.username else "owner";
    in
    {
    options = {
      flake = lib.mkOption {
        type = types.submodule {
          freeformType = types.attrsOf types.anything;
        };
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
        type = types.submodule {
          freeformType = types.attrsOf types.anything;
        };
        default = { };
      };
      rootPath = lib.mkOption {
        type = types.str;
        default = flakeOutPath;
      };
    };

    config = {
      systems = availableSystems;
      flake =
        flake
        // {
          inherit lib;
          meta =
            (flake.lib.meta or { })
            // {
              owner =
                ownerMeta
                // {
                  username = defaultOwnerUsername;
                };
            };
        };
      inputs = effectiveInputs;
      nixpkgs = { };
      rootPath = flakeOutPath;
      _module.args = filterAttrs (_: value: value != null) {
        inherit pinnedPkgs flakeOutPath flake;
        inputs = effectiveInputs;
        withSystem = defaultWithSystem;
          flake-parts-lib = flakePartsLib;
        };
      _module.check = false;
    };
  };

  specialArgs = filterAttrs (_: value: value != null) {
    inherit lib flake;
    pkgs = pinnedPkgs;
    inputs = effectiveInputs;
    rootPath = flakeOutPath;
    withSystem = defaultWithSystem;
  };

  normalizeModule = value:
    if builtins.isFunction value then value else (_: value);

  relativePath = path:
    if path == null then null else
      let
        asString = toString path;
        prefix = "${toString flakeRoot}/";
      in
      if lib.hasPrefix prefix asString then
        lib.removePrefix prefix asString
      else
        asString;

  getAttrSource = attrset: name:
    let
      pos = builtins.unsafeGetAttrPos name attrset;
    in
    if pos ? file && pos.file != "" then
      relativePath pos.file
    else
      null;

  aggregatorAllowedKeys = [ "imports" "_file" "attrPath" "default" "name" ];

  isAggregator = value:
    builtins.isAttrs value
    && value ? imports
    && (
      let
        attempt = builtins.tryEval value.imports;
      in
      attempt.success && builtins.isList attempt.value
    )
    && lib.all (key: lib.elem key aggregatorAllowedKeys) (builtins.attrNames value);

  collectModules =
    let
      recBind = rec {
        importsFor = value:
          let
            attempt = builtins.tryEval (
              if builtins.isAttrs value && value ? imports then value.imports else [ ]
            );
          in
          if attempt.success && builtins.isList attempt.value then
            attempt.value
          else
            [ ];

        collectValue = value: path: source:
          let
            nextSource =
              if builtins.isAttrs value && value ? _file then
                relativePath value._file
              else
                source;
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

        collectImportEntry = entry: path: source:
          let
            entrySource =
              if entry ? _file then relativePath entry._file else source;
            inner = importsFor entry;
          in
          lib.concatLists (
            map (
              child:
                if isAggregator child then
                  collectValue child path entrySource
                else if builtins.isAttrs child then
                  lib.concatLists (
                    lib.mapAttrsToList (
                      name: value:
                        collectValue value (path ++ [ name ]) entrySource
                    ) child
                  )
                else
                  [ ]
            ) inner
          );
      };
    in
    recBind.collectValue;

  # Collect module entries from flake.nixosModules
  moduleEntries =
    let
      modulesAttr = flake.nixosModules or { };
    in
    lib.concatLists (
      lib.mapAttrsToList (
        name: value:
          collectModules value [ name ] (getAttrSource modulesAttr name)
      ) modulesAttr
    );

  processModuleEntry =
    entry:
    let
      attempt = builtins.tryEval (
        let
          keyPath = entry.keyPath or [ ];
          namespace =
            if keyPath == [ ] then "root" else builtins.head keyPath;
          moduleName =
            if keyPath == [ ] then "module"
            else builtins.last keyPath;
          fullName =
            if keyPath == [ ] then "${namespace}/${moduleName}" else lib.concatStringsSep "/" keyPath;

          evaluation =
            builtins.tryEval (
              lib.evalModules {
                modules = [ moduleBase ] ++ flakePartsModules ++ [ entry.module ];
                inherit specialArgs;
              }
            );

          extraction =
            if evaluation.success then
              let
                extracted = builtins.tryEval (extractLib.extractModule evaluation.value);
              in
              if extracted.success then
                {
                  success = true;
                  value = extracted.value // {
                    meta = evaluation.value.config.meta or { };
                    moduleKeys = [ fullName ];
                  };
                }
              else
                {
                  success = false;
                  error = stringifyError extracted.value;
                }
            else
              {
                success = false;
                error = stringifyError evaluation.value;
              };

          metadata = {
            path = entry.sourcePath or "unknown";
            namespace = namespace;
            name = moduleName;
            fullName = fullName;
          };
        in
        metadata
        // {
          documentation = if extraction.success then extraction.value else null;
        error =
          if extraction.success then
            null
          else if evaluation.success then
            "Failed to extract module: ${extraction.error}"
          else
            "Failed to evaluate module: ${stringifyError evaluation.value}";
          extracted = extraction.success;
        }
      );
    in
    if attempt.success then
      attempt.value
    else
      {
        path = entry.sourcePath or "unknown";
        namespace = "root";
        name = "module";
        fullName = lib.concatStringsSep "/" (entry.keyPath or [ "root" "module" ]);
        documentation = null;
        error = "processModule failure: ${stringifyError attempt.value}";
        extracted = false;
      };

  processedModules = map processModuleEntry moduleEntries;
  successfulModules = processedModules;
  failedModules = processedModules;

  # Format module for JSON export
  formatModule =
    module:
    if !builtins.isAttrs module then
      {
        path = "unknown";
        namespace = "unknown";
        name = "unknown";
        fullName = "unknown";
        description = null;
        optionCount = 0;
        options = { };
        imports = [ ];
        meta = { };
      }
    else
      let
        modNamespace = module.namespace or "unknown";
        modName = module.name or "unknown";
        doc = module.documentation or null;
        docAttrs = builtins.isAttrs doc;
        docOptions = if docAttrs && doc ? options then doc.options else { };
        docMeta = if docAttrs && doc ? meta then doc.meta else { };
        docImports = if docAttrs && doc ? imports then map toString doc.imports else [ ];
        docModuleKeys = if docAttrs && doc ? moduleKeys then doc.moduleKeys else [ ];
      in
      {
        path = module.path or "unknown path";
        namespace = modNamespace;
        name = modName;
        fullName = module.fullName or "${modNamespace}/${modName}";

        description =
          if docAttrs && doc ? meta && doc.meta ? description then
            doc.meta.description
          else if docAttrs && doc ? options && docOptions ? description then
            docOptions.description.description or null
          else
            null;

        optionCount = builtins.length (lib.attrNames docOptions);

        options = lib.mapAttrs (name: opt: {
          inherit name;
          type = if opt ? type && opt.type ? name then opt.type.name else "unknown";
          description = opt.description or null;
          default =
            if opt ? default then
              if builtins.isFunction opt.default then "<function>" else opt.default
            else
              null;
          example =
            if opt ? example then
              if builtins.isFunction opt.example then "<function>" else opt.example
            else
              null;
        }) docOptions;

        imports = docImports;

        meta = docMeta
          // (if docModuleKeys != [ ] then { moduleKeys = docModuleKeys; } else { });
      };
  # Final output structure
  output = {
    generated = {
      timestamp = builtins.currentTime;
      nixpkgsRev = pkgs.lib.version or "unknown";
      extractorVersion = "1.0.0";
    };

    namespaces =
      let
        successList = builtins.filter (m: builtins.isAttrs m && (m.extracted or false)) processedModules;
        namespaceGroups = builtins.groupBy (m: m.namespace or "unknown") successList;
      in
      lib.mapAttrs (namespace: modules: {
        name = namespace;
        moduleCount = builtins.length modules;
        modules = map (m: m.fullName or "${namespace}/${m.name or "unknown"}") modules;
      }) namespaceGroups;

    stats =
      let
        successList = builtins.filter (m: builtins.isAttrs m && (m.extracted or false)) processedModules;
        failureList = builtins.filter (m: builtins.isAttrs m && !(m.extracted or false)) processedModules;
        namespaceGroups = builtins.groupBy (m: m.namespace or "unknown") successList;
        totalModules = builtins.length moduleEntries;
        extractedCount = builtins.length successList;
        failedCount = builtins.length failureList;
      in
      {
        total = totalModules;
        extracted = extractedCount;
        failed = failedCount;
        namespaces = lib.attrNames namespaceGroups;
        extractionRate = if totalModules > 0 then (extractedCount * 100) / totalModules else 0;
      };

    modules =
      let
        successList = builtins.filter (m: builtins.isAttrs m && (m.extracted or false)) processedModules;
      in
      map formatModule successList;

    errors =
      let
        failureList = builtins.filter (m: builtins.isAttrs m && !(m.extracted or false)) processedModules;
        sanitizeFailure = m: {
          path = m.path or "unknown path";
          error = m.error or "unknown error";
        };
      in
      map sanitizeFailure failureList;
  };

in
# Return the JSON-serializable output
output
