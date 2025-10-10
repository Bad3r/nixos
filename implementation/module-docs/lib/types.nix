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
      if builtins.isFunction option then
        {
          inherit name;
          type = {
            type = "function";
            value = "<function>";
          };
          default = null;
          defaultText = null;
          example = null;
          description = null;
          readOnly = false;
          visible = true;
          internal = false;
          hasApply = false;
          declarations = [ ];
        }
      else
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
            [ (extractOption fullName value) ]
          else if builtins.isAttrs value && !(value ? type) then
            extractOptions fullName value
          else
            [ (extractOption fullName value) ]
        ) opts
      );

    extractModule =
      args:
      let
        # Allow legacy callers to pass the evaluation attrset directly.
        evaluation = args.evaluation or args;

        evaluationOptions = evaluation.options or { };
        evaluationConfig = evaluation.config or { };
        flatOptions = extractOptions "" evaluationOptions;

        # Context for determining which declarations belong to this module.
        rawSourcePath = args.sourcePath or null;
        extraAllowed = args.allowedSourcePaths or [ ];
        configAllowed = (evaluationConfig.docExtraction or { }).allowedSourcePaths or [ ];
        rootPathRaw = args.rootPath or evaluationConfig.rootPath or null;

        normalizePath =
          path:
          if path == null then
            null
          else
            let
              str = toString path;
            in
            if lib.hasPrefix "./" str then lib.removePrefix "./" str else str;

        rootPath =
          let
            raw = normalizePath rootPathRaw;
          in
          if raw == "" then null else raw;

        allowedPaths =
          let
            combined =
              (
                if rawSourcePath == null then
                  [ ]
                else
                  [
                    normalizePath
                    rawSourcePath
                  ]
              )
              ++ (map normalizePath extraAllowed)
              ++ (map normalizePath configAllowed);
          in
          lib.unique (lib.filter (p: p != null && p != "") combined);

        relativizeToRoot =
          file:
          let
            str = normalizePath file;
          in
          if str == null || rootPath == null then
            str
          else if lib.hasPrefix "${rootPath}/" str then
            lib.removePrefix "${rootPath}/" str
          else
            str;

        declarationMatches =
          decl:
          let
            fileRaw = normalizePath (decl.file or null);
            fileRelative = relativizeToRoot (decl.file or null);
          in
          if fileRaw == null then
            false
          else
            lib.any (
              allowed:
              let
                candidate = if builtins.isFunction allowed then null else normalizePath allowed;
              in
              candidate != null
              && (fileRaw == candidate || fileRelative == candidate || lib.hasSuffix fileRaw candidate)
            ) allowedPaths;

        optionRelevant =
          option:
          let
            declarations = option.declarations or [ ];
          in
          if allowedPaths == [ ] then
            true
          else
            declarations != [ ] && lib.any declarationMatches declarations;

        filteredOptions = lib.filter optionRelevant flatOptions;
      in
      {
        options = lib.listToAttrs (map (opt: lib.nameValuePair opt.name opt) filteredOptions);
        config = extractConfig evaluationConfig;
        imports = evaluation.imports or [ ];
      };
  };

in
recFunctions
