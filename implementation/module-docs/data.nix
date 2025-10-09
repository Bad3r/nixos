{
  lib,
  flakeRoot ? ../../.,
  self,
  system,
}:
let
  graph = import ./graph.nix {
    inherit flakeRoot;
    flakeOverride = self;
    inherit system;
  };
  docLib = import ./lib { inherit lib; };

  sanitizeValue =
    value:
    if builtins.isAttrs value then
      lib.mapAttrs (_: sanitizeValue) value
    else if builtins.isList value then
      map sanitizeValue value
    else if builtins.isPath value then
      toString value
    else if builtins.isFunction value then
      "<function>"
    else
      value;

  normalizeModuleRecord =
    record:
    let
      data = record.data or { };
      attrPathList = data.attrPath or record.attrPath or [ ];
      attrPathString = data.attrPathString or lib.concatStringsSep "." attrPathList;
    in
    {
      inherit (record)
        namespace
        status
        error
        sourcePath
        ;
      attrPath = attrPathList;
      inherit attrPathString;
      skipReason = data.skipReason or null;
      tags = lib.attrByPath [ "meta" "tags" ] [ ] data;
      meta = data.meta or { };
      options = sanitizeValue (data.options or { });
      imports = map sanitizeValue (data.imports or [ ]);
      examples =
        if data ? examples then
          map (example: {
            option = example.option or "";
            example = sanitizeValue (example.example or null);
          }) data.examples
        else
          [ ];
      config = sanitizeValue (data.config or { });
    };

  namespaces = lib.mapAttrs (_: payload: payload.modules) graph.namespaces;
  normalizedNamespaces = lib.mapAttrs (_: modules: map normalizeModuleRecord modules) namespaces;
  summary = lib.mapAttrs (_: modules: docLib.summarizeModules modules) normalizedNamespaces;

in
{
  inherit normalizedNamespaces summary;
  modules = lib.concatLists (lib.attrValues normalizedNamespaces);
}
