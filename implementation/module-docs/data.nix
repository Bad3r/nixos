{
  lib,
  flakeRoot ? ../../.,
  self,
  inputs,
  system,
}:
let
  graph = import ./graph.nix {
    inherit flakeRoot;
    flakeOverride = self;
    inherit system;
  };
  docLib = import ./lib { inherit lib; };

  sanitizeExampleValue =
    value:
    if builtins.isAttrs value then
      lib.mapAttrs (_: sanitizeExampleValue) value
    else if builtins.isList value then
      map sanitizeExampleValue value
    else if builtins.isFunction value then
      "<function>"
    else
      value;

  normalizeModuleRecord =
    record:
    let
      data = record.data or { };
      attrPathList = data.attrPath or record.attrPath or [ ];
      attrPathString =
        if data ? attrPathString then data.attrPathString else lib.concatStringsSep "." attrPathList;
    in
    {
      inherit (record)
        namespace
        status
        error
        sourcePath
        ;
      attrPath = attrPathList;
      attrPathString = attrPathString;
      skipReason = if data ? skipReason then data.skipReason else null;
      tags = if data ? meta && data.meta ? tags then data.meta.tags else [ ];
      meta = if data ? meta then data.meta else { };
      options = if data ? options then sanitizeExampleValue data.options else { };
      imports = if data ? imports then data.imports else [ ];
      examples =
        if data ? examples then
          map (example: {
            option = example.option or "";
            example = sanitizeExampleValue (example.example or null);
          }) data.examples
        else
          [ ];
      config = if data ? config then sanitizeExampleValue data.config else { };
    };

  namespaces = lib.mapAttrs (_: payload: payload.modules) graph.namespaces;
  normalizedNamespaces = lib.mapAttrs (_: modules: map normalizeModuleRecord modules) namespaces;
  summary = lib.mapAttrs (_: modules: docLib.summarizeModules modules) normalizedNamespaces;

in
{
  inherit normalizedNamespaces summary;
  modules = lib.concatLists (lib.attrValues normalizedNamespaces);
}
