/*
  Package: rumdl
  Description: Markdown linter and formatter written in Rust.
  Homepage: https://rumdl.dev/
  Documentation: https://rumdl.dev/global-settings/
  Repository: https://github.com/rvben/rumdl

  Summary:
    * Lints Markdown with markdownlint-compatible rule IDs plus opt-in rules of its own.
    * Applies safe fixes in place and serves diagnostics over LSP for editors.

  Options:
    check: Lint files or directories and print diagnostics.
    check --fix: Apply automatic fixes where the rule supports them.
    fmt: Format files with formatter-style exit codes.
    rule: List rules, or show one rule's description.
    config: Print the effective configuration and the file it came from.
    --config: Read a specific configuration file or an inline TOML override.

  Notes:
    * Reads `.rumdl.toml` from the repository root; the `rumdl` pre-commit hook in `modules/meta/pre-commit.nix` runs it.
*/
_:
let
  RumdlModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.rumdl.extended;
    in
    {
      options.programs.rumdl.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable rumdl.";
        };

        package = lib.mkPackageOption pkgs "rumdl" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.rumdl = RumdlModule;
}
