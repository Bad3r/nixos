/*
  Package: yq-go
  Description: Portable command-line YAML, JSON, XML, CSV, and TOML processor.
  Homepage: https://mikefarah.gitbook.io/yq/
  Documentation: https://mikefarah.gitbook.io/yq/
  Repository: https://github.com/mikefarah/yq

  Summary:
    * Parses and transforms structured data with jq-like expressions, supporting merge, update, delete, and format conversion between YAML, JSON, XML, TOML, and CSV.
    * Single dependency-free binary written in Go with support for streaming, in-place edits, and piping from stdin.

  Options:
    -i, --inplace: Update the file in-place.
    -o, --output-format: Set output format (yaml, json, xml, toml, csv, tsv, props, base64).
    -p, --input-format: Force input format (yaml, json, xml, toml, csv, tsv, props, base64, lua, uri).
    -n, --null-input: Don't read input; evaluate expression from scratch.
    -e, --exit-status: Set exit status if no matches or null/false returned.
    -C, --colors: Force colored output.
    -I, --indent: Set indent level for output (default 2).
*/
_:
let
  YqGoModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."yq-go".extended;
    in
    {
      options.programs."yq-go".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable yq-go.";
        };

        package = lib.mkPackageOption pkgs "yq-go" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."yq-go" = YqGoModule;
}
