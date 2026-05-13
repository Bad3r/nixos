/*
  Package: searchfox-cli
  Description: Command-line interface for searching Mozilla codebases through searchfox.org.
  Homepage: nil
  Documentation: https://github.com/padenot/searchfox-cli#readme
  Repository: https://github.com/padenot/searchfox-cli

  Summary:
    * Searches Mozilla repositories through Searchfox text, symbol, path, and identifier queries.
    * Retrieves files and definitions, and inspects call graphs or C++ field layouts from the terminal.

  Options:
    -q, --query: Search for text or advanced Searchfox query syntax.
    -R, --repo: Select the Searchfox repository, defaulting to mozilla-central.
    --get-file: Fetch and print a file from the selected repository.
    --define: Find and display a symbol definition.
    --calls-from, --calls-to, --calls-between: Inspect Searchfox call graph relationships.
    --field-layout: Display C++ class or struct field layout information.
*/
_:
let
  SearchfoxCliModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."searchfox-cli".extended;
    in
    {
      options.programs.searchfox-cli.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable searchfox-cli.";
        };

        package = lib.mkPackageOption pkgs "searchfox-cli" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.searchfox-cli = SearchfoxCliModule;
}
