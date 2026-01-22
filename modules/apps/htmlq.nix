/*
  Package: htmlq
  Description: Like jq, but for HTML.
  Homepage: https://github.com/mgdm/htmlq
  Documentation: https://github.com/mgdm/htmlq#readme
  Repository: https://github.com/mgdm/htmlq

  Summary:
    * Runs CSS selectors on HTML input and outputs matching elements.
    * Extracts attributes, text content, or pretty-printed HTML from selections.

  Options:
    -a: Only return the specified attribute from selected elements.
    -t: Output only the contents of text nodes inside selected elements.
    -p: Pretty-print the serialised output.
    -r: Remove nodes matching selector before output.
    -b: Use specified URL as the base for relative links.
    -B: Detect base URL from the <base> tag in the document.
    -w: Ignore text nodes consisting entirely of whitespace.
*/
_:
let
  HtmlqModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.htmlq.extended;
    in
    {
      options.programs.htmlq.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable htmlq.";
        };

        package = lib.mkPackageOption pkgs "htmlq" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.htmlq = HtmlqModule;
}
