{ lib }:
typesLib:
let
  inherit (typesLib)
    extractModule
    extractOption
    extractType
    extractDeclarations
    extractConfig
    ;

  sanitizeValue =
    value:
    if builtins.isFunction value then
      "<function>"
    else if builtins.isPath value then
      toString value
    else if builtins.isAttrs value then
      lib.mapAttrs (_: sanitizeValue) value
    else if builtins.isList value then
      map sanitizeValue value
    else
      value;

  collectExamples =
    module:
    let
      options = module.options or { };
      recurse =
        prefix: opts:
        lib.concatLists (
          lib.mapAttrsToList (
            name: value:
            let
              fullName = if prefix == "" then name else "${prefix}.${name}";
            in
            if value ? example && value.example != null then
              [
                {
                  option = fullName;
                  example = if builtins.isFunction value.example then "<function>" else sanitizeValue value.example;
                }
              ]
            else if builtins.isAttrs value && !(value ? type) then
              recurse fullName value
            else if builtins.isFunction value then
              [ ]
            else
              [ ]
          ) opts
        );
    in
    recurse "" options;

  moduleDocFromEvaluation =
    {
      namespace,
      attrPath,
      sourcePath,
      originSystem,
      skipReason ? null,
      evaluation,
      meta ? { },
    }:
    let
      extracted = extractModule evaluation;
      attrPathList = if builtins.isList attrPath then attrPath else [ attrPath ];
      attrPathString = lib.concatStringsSep "." attrPathList;
    in
    {
      inherit
        namespace
        sourcePath
        originSystem
        skipReason
        ;
      attrPath = attrPathList;
      attrPathString = attrPathString;
      options = sanitizeValue extracted.options;
      imports = extracted.imports;
      config = sanitizeValue extracted.config;
      meta = meta // {
        skipReason = skipReason;
        attrPath = attrPathString;
      };
      examples = [ ];
    };

in
{
  inherit sanitizeValue collectExamples moduleDocFromEvaluation;
}
