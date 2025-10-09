{
  config,
  lib,
  inputs,
  ...
}:
let
  systems = config.systems;
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
        moduleDocsJson = moduleDocsJson;
        moduleDocsMarkdown = moduleDocsMarkdown;
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
      packages.module-docs-json = moduleDocsJson;
      packages.module-docs-markdown = moduleDocsMarkdown;
      packages.module-docs-exporter = moduleDocsExporter;
      packages.module-docs-bundle = moduleDocsBundle;
      packages.moduleDocsBundle = moduleDocsBundle;
      packages.moduleDocsJson = moduleDocsJson;
      packages.moduleDocsMarkdown = moduleDocsMarkdown;
      packages.moduleDocsExporter = moduleDocsExporter;
      apps."module-docs-exporter" = {
        type = "app";
        program = "${moduleDocsExporter}/bin/module-docs-exporter";
      };
      apps.moduleDocsExporter = {
        type = "app";
        program = "${moduleDocsExporter}/bin/module-docs-exporter";
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
