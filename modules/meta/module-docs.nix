{
  config,
  lib,
  inputs,
  ...
}:
let
  inherit (config) systems;
  bundleName = "moduleDocsBundle";
in
{
  perSystem =
    { pkgs, ... }:
    let
      moduleDocsJson = pkgs.callPackage ../../packages/module-docs-json {
        inherit lib pkgs;
        self = inputs.self or { };
        inherit inputs;
      };
      moduleDocsMarkdown = pkgs.callPackage ../../packages/module-docs-markdown {
        inherit lib pkgs;
        self = inputs.self or { };
        inherit inputs;
      };
      moduleDocsExporter = pkgs.callPackage ../../packages/module-docs-exporter {
        inherit pkgs lib;
        inherit moduleDocsJson;
        inherit moduleDocsMarkdown;
      };
      moduleDocsBundle = pkgs.symlinkJoin {
        name = "module-docs-bundle";
        paths = [
          moduleDocsJson
          moduleDocsMarkdown
        ];
      };
    in
    {
      packages = {
        module-docs-json = moduleDocsJson;
        module-docs-markdown = moduleDocsMarkdown;
        module-docs-exporter = moduleDocsExporter;
        module-docs-bundle = moduleDocsBundle;
      };
      apps = {
        "module-docs-exporter" = {
          type = "app";
          program = "${moduleDocsExporter}/bin/module-docs-exporter";
        };
      };
      checks.module-docs = pkgs.runCommand "module-docs-check" { } ''
        ${moduleDocsExporter}/bin/module-docs-exporter --format json --out $TMPDIR/module-docs
        touch $out
      '';
    };

  flake.${bundleName} = lib.genAttrs systems (
    system:
    let
      ps = config.perSystem.${system};
    in
    {
      inherit (ps.packages)
        module-docs-json
        module-docs-markdown
        module-docs-exporter
        module-docs-bundle
        ;
    }
  );
}
