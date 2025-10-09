{ lib }:
typesLib:
let
  inherit (typesLib) extractModule;

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
      inherit attrPathString;
      options = sanitizeValue extracted.options;
      inherit (extracted) imports;
      config = sanitizeValue extracted.config;
      meta = meta // {
        inherit skipReason;
        attrPath = attrPathString;
      };
      examples = [ ];
    };

in
{
  inherit sanitizeValue moduleDocFromEvaluation;
}
