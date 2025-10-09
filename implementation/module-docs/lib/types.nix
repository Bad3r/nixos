{ lib }:
let
  inherit (lib) types;
  recFunctions = rec {
    extractType =
      type:
      if type ? _type && type._type == "option-type" then
        extractOptionType type
      else if type ? _type && type._type == "submodule" then
        extractSubmodule type
      else if type == types.unspecified || type == null then
        {
          type = "unspecified";
          value = null;
        }
      else if builtins.isString type then
        {
          type = "primitive";
          value = type;
        }
      else
        {
          type = "unknown";
          value = toString type;
        };

    extractOptionType =
      type:
      {
        type = "option-type";
        name = type.name or "unnamed";
        description = type.description or null;
        check = type.check or null;
        merge = type.merge or null;
      }
      // (
        if type.name == "attrsOf" || type.name == "lazyAttrsOf" then
          { nestedType = extractType type.nestedTypes.elemType; }
        else if type.name == "listOf" then
          { nestedType = extractType type.nestedTypes.elemType; }
        else if type.name == "nullOr" then
          { nestedType = extractType type.nestedTypes.elemType; }
        else if type.name == "either" then
          {
            left = extractType (builtins.elemAt type.nestedTypes.elemTypes 0);
            right = extractType (builtins.elemAt type.nestedTypes.elemTypes 1);
          }
        else if type.name == "oneOf" then
          { types = map extractType type.nestedTypes.elemTypes; }
        else if type.name == "enum" then
          { values = type.functor.payload; }
        else if type.name == "functionTo" then
          { returnType = extractType type.nestedTypes.elemType; }
        else if type.name == "submodule" then
          extractSubmodule type.functor.payload
        else if type ? nestedTypes && type.nestedTypes ? elemType then
          { nestedType = extractType type.nestedTypes.elemType; }
        else
          { }
      );

    extractSubmodule =
      submodule:
      let
        config =
          if submodule ? options then
            submodule
          else if submodule ? getSubOptions then
            submodule.getSubOptions [ ]
          else if builtins.isFunction submodule then
            submodule { }
          else
            { };
        options = config.options or { };
      in
      {
        type = "submodule";
        options = lib.mapAttrs extractOption options;
        imports = config.imports or [ ];
        config = if config ? config then extractConfig config.config else null;
      };

    extractDeclarations =
      option:
      let
        declarations = option.declarations or [ ];
        formatDeclaration =
          decl:
          if builtins.isString decl then
            {
              file = decl;
              line = null;
              column = null;
            }
          else if decl ? file then
            {
              inherit (decl) file;
              line = decl.line or null;
              column = decl.column or null;
              url = decl.url or null;
            }
          else
            {
              file = toString decl;
              line = null;
              column = null;
            };
      in
      map formatDeclaration declarations;

    extractConfig =
      config:
      if builtins.isAttrs config then
        lib.mapAttrs (
          _: value:
          if builtins.isFunction value then
            "<function>"
          else if builtins.isAttrs value && value ? _type then
            "<${value._type}>"
          else if builtins.isList value then
            map (v: if builtins.isAttrs v then extractConfig v else v) value
          else
            value
        ) config
      else
        config;

    extractOption =
      name: option:
      let
        opt =
          if option ? _type && option._type == "option" then
            option
          else if option ? type then
            option
          else
            { type = types.unspecified; };
      in
      {
        inherit name;
        type = extractType (opt.type or types.unspecified);
        default = opt.default or null;
        defaultText = opt.defaultText or null;
        example = opt.example or null;
        description = opt.description or null;
        readOnly = opt.readOnly or false;
        visible = opt.visible or true;
        internal = opt.internal or false;
        hasApply = opt ? apply;
        declarations = extractDeclarations opt;
      };

    extractOptions =
      prefix: opts:
      lib.concatLists (
        lib.mapAttrsToList (
          name: value:
          let
            fullName = if prefix == "" then name else "${prefix}.${name}";
          in
          if value ? _type && value._type == "option" then
            [
              extractOption
              fullName
              value
            ]
          else if builtins.isAttrs value && !(value ? type) then
            extractOptions fullName value
          else
            [
              extractOption
              fullName
              value
            ]
        ) opts
      );

    extractModule =
      evaluatedModule:
      let
        options = evaluatedModule.options or { };
        config = evaluatedModule.config or { };
        flatOptions = extractOptions "" options;
      in
      {
        options = lib.listToAttrs (map (opt: lib.nameValuePair opt.name opt) flatOptions);
        config = extractConfig config;
        imports = evaluatedModule.imports or [ ];
      };
  };

in
recFunctions
