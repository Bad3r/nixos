/**
 * NixOS Module Extraction Library
 * Extracts and transforms NixOS module definitions for documentation
 */

{ lib, pkgs }:
rec {
  /**
   * Extract type information from a Nix type
   */
  extractType = type:
    if type ? _type && type._type == "option-type" then
      extractOptionType type
    else if type ? _type && type._type == "submodule" then
      extractSubmodule type
    else
      { type = "unknown"; value = toString type; };

  /**
   * Extract option type details
   */
  extractOptionType = type: {
    type = "option-type";
    name = type.name or "unnamed";
    description = type.description or null;
    check = type.check or null;
    merge = type.merge or null;
  } // (
    # Handle nested types
    if type.name == "attrsOf" || type.name == "lazyAttrsOf" then {
      nestedType = extractType type.nestedTypes.elemType;
    } else if type.name == "listOf" then {
      nestedType = extractType type.nestedTypes.elemType;
    } else if type.name == "nullOr" then {
      nestedType = extractType type.nestedTypes.elemType;
    } else if type.name == "either" then {
      left = extractType (builtins.elemAt type.nestedTypes.elemTypes 0);
      right = extractType (builtins.elemAt type.nestedTypes.elemTypes 1);
    } else if type.name == "oneOf" then {
      types = map extractType type.nestedTypes.elemTypes;
    } else if type.name == "enum" then {
      values = type.functor.payload;
    } else if type.name == "functionTo" then {
      returnType = extractType type.nestedTypes.elemType;
    } else if type.name == "submodule" then
      extractSubmodule type.functor.payload
    else if type ? nestedTypes && type.nestedTypes ? elemType then {
      nestedType = extractType type.nestedTypes.elemType;
    } else {}
  );

  /**
   * Extract submodule information
   */
  extractSubmodule = submodule:
    let
      # Handle both direct submodule configs and wrapped ones
      config =
        if submodule ? options then submodule
        else if submodule ? getSubOptions then submodule.getSubOptions []
        else if builtins.isFunction submodule then submodule {}
        else {};

      options = config.options or {};
    in {
      type = "submodule";
      options = lib.mapAttrs extractOption options;
      imports = config.imports or [];
      config = if config ? config then extractConfig config.config else null;
    };

  /**
   * Extract option information
   */
  extractOption = name: option:
    let
      # Handle different option formats
      opt =
        if option ? _type && option._type == "option" then option
        else if option ? type then option
        else { type = lib.types.unspecified; };
    in {
      name = name;
      type = extractType (opt.type or lib.types.unspecified);
      default = opt.default or null;
      defaultText = opt.defaultText or null;
      example = opt.example or null;
      description = opt.description or null;
      readOnly = opt.readOnly or false;
      visible = opt.visible or true;
      internal = opt.internal or false;
      apply = if opt ? apply then true else false;
      hasApply = opt ? apply;
      declarations = extractDeclarations opt;
    };

  /**
   * Extract option declarations
   */
  extractDeclarations = option:
    let
      declarations = option.declarations or [];
      formatDeclaration = decl:
        if builtins.isString decl then {
          file = decl;
          line = null;
          column = null;
        } else if decl ? file then {
          inherit (decl) file;
          line = decl.line or null;
          column = decl.column or null;
          url = decl.url or null;
        } else {
          file = toString decl;
          line = null;
          column = null;
        };
    in map formatDeclaration declarations;

  /**
   * Extract configuration values
   */
  extractConfig = config:
    if builtins.isAttrs config then
      lib.mapAttrs (name: value:
        if builtins.isFunction value then
          "<function>"
        else if builtins.isAttrs value && value ? _type then
          "<${value._type}>"
        else if builtins.isList value then
          map (v: if builtins.isAttrs v then extractConfig v else v) value
        else
          value
      ) config
    else config;

  /**
   * Extract complete module information
   */
  extractModule = evaluatedModule:
    let
      options = evaluatedModule.options or {};
      config = evaluatedModule.config or {};

      # Flatten nested options
      flattenOptions = prefix: opts:
        lib.concatLists (lib.mapAttrsToList (name: value:
          let
            fullName = if prefix == "" then name else "${prefix}.${name}";
          in
            if value ? _type && value._type == "option" then
              [{ name = fullName; option = extractOption fullName value; }]
            else if builtins.isAttrs value && !(value ? type) then
              flattenOptions fullName value
            else
              [{ name = fullName; option = extractOption fullName value; }]
        ) opts);

      flatOptions = flattenOptions "" options;
    in {
      options = lib.listToAttrs (map (x: lib.nameValuePair x.name x.option) flatOptions);
      config = extractConfig config;
      declarations = [];
      imports = evaluatedModule.imports or [];
    };

  /**
   * Extract module info without evaluation
   */
  extractModuleInfo = module:
    if builtins.isPath module then
      extractModuleInfo (import module { inherit lib pkgs; })
    else if builtins.isFunction module then
      extractModuleInfo (module { inherit lib pkgs; })
    else {
      options = lib.mapAttrs extractOption (module.options or {});
      imports = map toString (module.imports or []);
      config = extractConfig (module.config or {});
      meta = module.meta or {};
    };

  /**
   * Batch extract multiple modules
   */
  extractModules = modules:
    map extractModuleInfo modules;

  /**
   * Extract and serialize module for JSON export
   */
  serializeModule = module:
    let
      extracted = extractModuleInfo module;

      # Convert functions and complex types to strings
      sanitize = value:
        if builtins.isFunction value then
          "<function>"
        else if builtins.isAttrs value then
          lib.mapAttrs (n: sanitize) value
        else if builtins.isList value then
          map sanitize value
        else if value == null then
          null
        else
          toString value;
    in sanitize extracted;

  /**
   * Extract module examples
   */
  extractExamples = module:
    let
      options = module.options or {};

      collectExamples = prefix: opts:
        lib.concatLists (lib.mapAttrsToList (name: value:
          let
            fullName = if prefix == "" then name else "${prefix}.${name}";
          in
            if value ? example then
              [{ option = fullName; example = value.example; }]
            else if builtins.isAttrs value && !(value ? type) then
              collectExamples fullName value
            else
              []
        ) opts);
    in collectExamples "" options;

  /**
   * Extract module metadata
   */
  extractMetadata = module: {
    description = module.meta.description or null;
    maintainers = module.meta.maintainers or [];
    doc = module.meta.doc or null;
    buildDocsInSandbox = module.meta.buildDocsInSandbox or true;
  };

  /**
   * Validate extracted module
   */
  validateExtracted = extracted:
    let
      hasRequiredFields =
        extracted ? options &&
        builtins.isAttrs extracted.options;

      optionsValid = lib.all (opt:
        opt ? name && opt ? type
      ) (lib.attrValues (extracted.options or {}));
    in {
      valid = hasRequiredFields && optionsValid;
      errors =
        (if !hasRequiredFields then ["Missing required fields"] else []) ++
        (if !optionsValid then ["Invalid option structure"] else []);
    };

  /**
   * Generate module documentation
   */
  generateDocumentation = module:
    let
      extracted = extractModuleInfo module;
      metadata = extractMetadata module;
      examples = extractExamples module;
    in {
      inherit metadata examples;
      module = extracted;
      generated = {
        timestamp = builtins.currentTime;
        version = "1.0.0";
      };
    };
}