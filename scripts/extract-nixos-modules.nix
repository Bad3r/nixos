# Extract NixOS modules documentation data for Cloudflare Workers API
{ pkgs ? import <nixpkgs> {}
, lib ? pkgs.lib
, flakeRoot ? ./.
}:

let
  # Import the extraction library
  extractLib = import (flakeRoot + /implementation/lib/extract-modules.nix) { inherit lib pkgs; };

  # Helper to safely get module path
  getModulePath = module:
    if builtins.isPath module then
      lib.removePrefix "${flakeRoot}/" (toString module)
    else if builtins.isAttrs module && module ? _file then
      lib.removePrefix "${flakeRoot}/" module._file
    else if builtins.isString module then
      module
    else
      "unknown";

  # Helper to determine namespace from path
  getNamespace = path:
    let
      parts = lib.splitString "/" path;
    in
      if lib.hasPrefix "modules/" path then
        lib.elemAt parts 1
      else
        "root";

  # Helper to determine module name from path
  getModuleName = path:
    let
      basename = lib.last (lib.splitString "/" path);
      withoutExt = lib.removeSuffix ".nix" basename;
    in
      if withoutExt == "default" then
        lib.last (lib.init (lib.splitString "/" path))
      else
        withoutExt;

  # Process a single module file
  processModule = modulePath:
    let
      fullPath = "${flakeRoot}/${modulePath}";

      # Try to import and evaluate the module
      moduleContent =
        if builtins.pathExists fullPath then
          builtins.tryEval (import fullPath)
        else
          { success = false; value = null; };

      # Extract module documentation
      extracted =
        if moduleContent.success then
          let
            extractResult = builtins.tryEval (extractLib.extractModuleInfo moduleContent.value);
          in
            if extractResult.success then
              extractResult.value
            else
              { error = "Failed to extract module"; }
        else
          { error = "Module not found or invalid"; };

      # Build module metadata
      metadata = {
        path = modulePath;
        namespace = getNamespace modulePath;
        name = getModuleName modulePath;
        fullName = "${getNamespace modulePath}/${getModuleName modulePath}";
      };

    in
      metadata // {
        documentation = if extracted ? error then null else extracted;
        error = extracted.error or null;
        extracted = !( extracted ? error);
      };

  # Scan modules directory for all .nix files
  scanModuleDirectory = dir:
    let
      # Recursively find all .nix files
      findNixFiles = path:
        let
          content = builtins.readDir path;
          processEntry = name: type:
            let
              fullPath = "${path}/${name}";
              relativePath = lib.removePrefix "${flakeRoot}/" fullPath;
            in
              if type == "directory" && !lib.hasPrefix "_" name then
                findNixFiles fullPath
              else if type == "regular" && lib.hasSuffix ".nix" name && !lib.hasPrefix "_" name then
                [ relativePath ]
              else
                [];
        in
          lib.concatLists (lib.mapAttrsToList processEntry content);
    in
      findNixFiles dir;

  # Get all module files
  moduleFiles = scanModuleDirectory "${flakeRoot}/modules";

  # Process all modules
  processedModules = map processModule moduleFiles;

  # Separate successfully extracted modules from errors
  successfulModules = lib.filter (m: m.extracted) processedModules;
  failedModules = lib.filter (m: !m.extracted) processedModules;

  # Group modules by namespace
  modulesByNamespace = lib.groupBy (m: m.namespace) successfulModules;

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

  # Format module for JSON export
  formatModule = module: {
    inherit (module) path namespace name fullName;

    description =
      if module.documentation ? meta && module.documentation.meta ? description then
        module.documentation.meta.description
      else if module.documentation ? options && module.documentation.options ? description then
        module.documentation.options.description.description or null
      else
        null;

    optionCount =
      if module.documentation ? options then
        builtins.length (lib.attrNames module.documentation.options)
      else
        0;

    options =
      if module.documentation ? options then
        lib.mapAttrs (name: opt: {
          inherit name;
          type =
            if opt ? type && opt.type ? name then
              opt.type.name
            else
              "unknown";
          description = opt.description or null;
          default =
            if opt ? default then
              if builtins.isFunction opt.default then
                "<function>"
              else if opt.default == null then
                null
              else
                toString opt.default
            else
              null;
          example =
            if opt ? example then
              if builtins.isFunction opt.example then
                "<function>"
              else if opt.example == null then
                null
              else
                toString opt.example
            else
              null;
        }) module.documentation.options
      else
        {};

    imports =
      if module.documentation ? imports then
        map toString module.documentation.imports
      else
        [];

    meta =
      if module.documentation ? meta then
        module.documentation.meta
      else
        {};
  };

  # Final output structure
  output = {
    generated = {
      timestamp = builtins.currentTime;
      nixpkgsRev = pkgs.lib.version or "unknown";
      extractorVersion = "1.0.0";
    };

    inherit stats;

    modules = map formatModule successfulModules;

    namespaces = lib.mapAttrs (namespace: modules: {
      name = namespace;
      moduleCount = builtins.length modules;
      modules = map (m: m.fullName) modules;
    }) modulesByNamespace;

    errors = map (m: {
      path = m.path;
      error = m.error;
    }) failedModules;
  };

in
  # Return the JSON-serializable output
  output