/*
  Package: ast-grep
  Description: Fast and polyglot tool for code searching, linting, rewriting at large scale.
  Homepage: https://ast-grep.github.io/
  Documentation: https://ast-grep.github.io/reference/cli.html
  Repository: https://github.com/ast-grep/ast-grep

  Summary:
    * Searches source code structurally using AST patterns instead of plain-text matching.
    * Runs reusable rule sets for linting and can rewrite matching code directly from the CLI.

  Options:
    run: Execute a one-shot structural search or rewrite from the command line.
    scan: Apply configured rules across a codebase using `sgconfig.yml` or a specific rule file.
    test: Validate rule behavior against test fixtures and snapshots.
    new: Scaffold ast-grep projects, rules, tests, or utility rules.
    lsp: Start the language server for editor diagnostics.
*/
_:
let
  AstGrepModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."ast-grep".extended;
    in
    {
      options.programs.ast-grep.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable ast-grep.";
        };

        package = lib.mkPackageOption pkgs "ast-grep" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.ast-grep = AstGrepModule;
}
