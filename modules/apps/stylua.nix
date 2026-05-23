/*
  Package: stylua
  Description: Opinionated Lua code formatter.
  Homepage: nil
  Documentation: nil
  Repository: https://github.com/JohnnyMorganz/StyLua

  Summary:
    * Formats Lua source files and can check formatting without overwriting input.
    * Reads StyLua and EditorConfig settings for project-local formatter behavior.

  Options:
    --check: Compare formatting without overwriting files.
    --config-path: Specify a stylua.toml configuration file.
    --glob: Select or ignore files with glob patterns.
    --stdin-filepath: Provide a path context for stdin input.
    --verify: Check formatted output correctness.
*/
_:
let
  StyluaModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.stylua.extended;
    in
    {
      options.programs.stylua.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable stylua.";
        };

        package = lib.mkPackageOption pkgs "stylua" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.stylua = StyluaModule;
}
