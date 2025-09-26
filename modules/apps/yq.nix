/*
  Package: yq
  Description: Portable command-line processor for YAML, JSON, XML, and CSV, built on jq-like syntax.
  Homepage: https://mikefarah.gitbook.io/yq/
  Documentation: https://mikefarah.gitbook.io/yq/
  Repository: https://github.com/mikefarah/yq

  Summary:
    * Parses and transforms structured data (YAML/JSON/XML) with expressions similar to jq, supporting merge, update, delete, and format conversion.
    * Supports streaming, eval-style scripting, in-place edits, and integration with jq via `yq eval`.

  Options:
    yq eval '<expression>' <file>: Evaluate expressions to query or modify data.
    yq eval -i '<expression>' <file>: Modify files in place.
    yq eval '... | to_json' <file>: Convert YAML to JSON.
    yq --null-input '<expression>': Evaluate expressions without input file (e.g. constructing YAML/JSON).
    yq eval-all '...': Merge multiple documents at once.

  Example Usage:
    * `yq eval '.services[0].name' docker-compose.yml` — Extract a value from a YAML file.
    * `yq eval '.metadata.labels += {env:"prod"}' -i deployment.yaml` — Append labels in place.
    * `yq eval -o=json '.items[]' config.yaml` — Convert YAML items to JSON.
*/

{
  flake.nixosModules.apps.yq =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.yq ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.yq ];
    };
}
