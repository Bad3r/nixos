/*
  Package: jq
  Description: Lightweight and flexible command-line JSON processor.
  Homepage: https://jqlang.github.io/jq/
  Documentation: https://jqlang.github.io/jq/manual/
  Repository: https://github.com/jqlang/jq

  Summary:
    * Provides a functional programming language for querying, transforming, and generating JSON data streams.
    * Integrates easily into shell pipelines, supporting streaming, filtering, and complex transformations.

  Options:
    -c: Compact output by removing unnecessary whitespace.
    -r: Output raw strings instead of quoted JSON strings.
    -s: Slurp all inputs into an array before processing.
    -f <file>: Load filters from a file rather than command line.

  Notes:
    * Package installation handled by NixOS module at modules/apps/jq.nix.
*/
_: {
  flake.homeManagerModules.apps.jq =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "jq" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.jq = {
          enable = true;
          package = null;
        };
      };
    };
}
