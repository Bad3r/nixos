{
  lib,
  pkgs,
  self,
  inputs ? { },
  flakeRoot ? ../../.,
}:
let
  data = import ./data.nix {
    inherit lib flakeRoot self;
    inherit (pkgs) system;
  };
  docLib = import ./lib { inherit lib; };
  combinedInputs = inputs // (self.inputs or { });
  nixpkgsInput = combinedInputs.nixpkgs or { };

  normalizeModuleRecord = module: {
    inherit (module)
      namespace
      status
      error
      sourcePath
      attrPath
      attrPathString
      skipReason
      tags
      meta
      options
      imports
      examples
      config
      ;
  };

  namespaces = data.normalizedNamespaces;
  normalizedNamespaces = lib.mapAttrs (_: modules: map normalizeModuleRecord modules) namespaces;
  errorsNdjson = lib.concatMap (modules: lib.filter (mod: mod.status == "error") modules) (
    lib.attrValues normalizedNamespaces
  );

  metadata = {
    generator = "module-docs-json";
    inherit (pkgs) system;
    nixpkgsRevision = nixpkgsInput.rev or nixpkgsInput.shortRev or null;
    flakeRevision = self.rev or null;
    moduleCount = lib.length data.modules;
    namespaceCount = lib.length (lib.attrNames normalizedNamespaces);
  };

  jsonBody = {
    inherit metadata;
    namespaces = lib.mapAttrs (_: modules: {
      stats = docLib.summarizeModules modules;
      inherit modules;
    }) normalizedNamespaces;
  };

  errorsPayload = map (module: {
    inherit (module)
      namespace
      attrPathString
      error
      sourcePath
      ;
  }) errorsNdjson;

in
pkgs.runCommand "module-docs-json" { } ''
    out_dir=$out/share/module-docs
    mkdir -p "$out_dir"
    cat >"$out_dir/modules.json" <<'JSON'
  ${builtins.toJSON jsonBody}
  JSON
    ${lib.optionalString (errorsPayload != [ ]) ''
          cat >"$out_dir/errors.ndjson" <<'NDJSON'
      ${lib.concatStringsSep "\n" (map builtins.toJSON errorsPayload)}
      NDJSON
    ''}
''
