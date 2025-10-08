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

  moduleBase = {
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
      inherit flake;
      inherit (flake) inputs;
      nixpkgs = { };
      rootPath = flakeOutPath;
      _module.args = filterAttrs (_: value: value != null) {
        inherit pinnedPkgs flakeOutPath flake;
        inputs = flakeInputs;
        withSystem = defaultWithSystem;
        flake-parts-lib = flakePartsLib;
      };
      _module.check = false;
    };
  };

  specialArgs = filterAttrs (_: value: value != null) {
    inherit lib flake;
    pkgs = pinnedPkgs;
    inputs = flakeInputs;
    rootPath = flakeOutPath;
    withSystem = defaultWithSystem;
  };

  evaluateModule =
    modulePath:
    let
      moduleSpec = if builtins.isPath modulePath then modulePath else flakeOutPath + "/${modulePath}";
    in
    lib.evalModules {
      modules = [ moduleBase ] ++ flakePartsModules ++ [ moduleSpec ];
      inherit specialArgs;
    };

  # Helper to determine namespace from path
  getNamespace =
    path:
    let
      parts = lib.splitString "/" path;
    in
    if lib.hasPrefix "modules/" path then lib.elemAt parts 1 else "root";

  # Helper to determine module name from path
  getModuleName =
    path:
    let
      basename = lib.last (lib.splitString "/" path);
      withoutExt = lib.removeSuffix ".nix" basename;
    in
    if withoutExt == "default" then lib.last (lib.init (lib.splitString "/" path)) else withoutExt;

  # Process a single module file
  processModule =
    modulePath:
    let
      attempt = builtins.tryEval (
        let
          localPath = flakeRoot + "/${modulePath}";

          evaluation =
            if builtins.pathExists localPath then
              builtins.tryEval (evaluateModule modulePath)
            else
              {
                success = false;
                value = "Module path not found";
              };

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
                  };
                }
              else
                {
                  success = false;
                  error = extracted.value;
                }
            else
              {
                success = false;
                error = evaluation.value;
              };

          metadata = {
            path = modulePath;
            namespace = getNamespace modulePath;
            name = getModuleName modulePath;
            fullName = "${getNamespace modulePath}/${getModuleName modulePath}";
          };
        in
        metadata
        // {
          documentation = if extraction.success then extraction.value else null;
          error =
            if extraction.success then
              null
            else if evaluation.success then
              "Failed to extract module: ${stringifyError extraction.error}"
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
        path = modulePath;
        namespace = getNamespace modulePath;
        name = getModuleName modulePath;
        fullName = "${getNamespace modulePath}/${getModuleName modulePath}";
        documentation = null;
        error = "processModule failure: ${stringifyError attempt.value}";
        extracted = false;
      };

  # Scan modules directory for all .nix files
  scanModuleDirectory =
    dir:
    let
      # Recursively find all .nix files
      findNixFiles =
        path:
        let
          content = builtins.readDir path;
          processEntry =
            name: type:
            let
              fullPath = path + "/${name}";
              relativePath = lib.removePrefix "${toString flakeRoot}/" (toString fullPath);
            in
            if type == "directory" && !lib.hasPrefix "_" name then
              findNixFiles fullPath
            else if type == "regular" && lib.hasSuffix ".nix" name && !lib.hasPrefix "_" name then
              [ relativePath ]
            else
              [ ];
        in
        lib.concatLists (lib.mapAttrsToList processEntry content);
    in
    findNixFiles dir;

  # Get all module files
  moduleFiles = scanModuleDirectory (flakeRoot + "/modules");

  # Process all modules
  processedModules = map processModule moduleFiles;
<<<<<<< HEAD
  successfulModules = processedModules;
  failedModules = processedModules;
=======

  # Separate successfully extracted modules from errors
  successfulModules = builtins.filter (
    m: builtins.isAttrs m && (m.extracted or false)
  ) processedModules;
  sanitizedSuccess = builtins.filter builtins.isAttrs successfulModules;
  failedModules = builtins.filter (m: builtins.isAttrs m && !(m.extracted or false)) processedModules;

  # Group modules by namespace
  modulesByNamespace = builtins.groupBy (m: m.namespace or "unknown") sanitizedSuccess;

  # Calculate statistics
  stats = {
    total = builtins.length moduleFiles;
    extracted = builtins.length successfulModules;
    failed = builtins.length failedModules;
    namespaces = lib.attrNames modulesByNamespace;
    extractionRate =
      if builtins.length moduleFiles > 0 then
        (builtins.length successfulModules * 100) / builtins.length moduleFiles
      else
        0;
  };
>>>>>>> b47062b4e (chore: apply treefmt exclusions and secret fixes)

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

        meta = docMeta;
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

<<<<<<< HEAD
    stats =
      let
        successList = builtins.filter (m: builtins.isAttrs m && (m.extracted or false)) processedModules;
        failureList = builtins.filter (m: builtins.isAttrs m && !(m.extracted or false)) processedModules;
        namespaceGroups = builtins.groupBy (m: m.namespace or "unknown") successList;
        totalModules = builtins.length moduleFiles;
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
=======
    modules = sanitizedSuccess;
>>>>>>> b47062b4e (chore: apply treefmt exclusions and secret fixes)

    modules =
      let
        successList = builtins.filter (m: builtins.isAttrs m && (m.extracted or false)) processedModules;
      in
      map formatModule successList;

<<<<<<< HEAD
    errors =
      let
        failureList = builtins.filter (m: builtins.isAttrs m && !(m.extracted or false)) processedModules;
        sanitizeFailure = m: {
          path = m.path or "unknown path";
          error = m.error or "unknown error";
        };
      in
      map sanitizeFailure failureList;
=======
    errors = [ ];
>>>>>>> b47062b4e (chore: apply treefmt exclusions and secret fixes)
  };

in
# Return the JSON-serializable output
output
