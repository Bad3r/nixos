/*
  Package: tweakcc
  Description: CLI tool to customize Claude Code themes, thinking verbs, and system prompts.
  Homepage: https://github.com/Piebald-AI/tweakcc
  Documentation: https://github.com/Piebald-AI/tweakcc#readme
  Repository: https://github.com/Piebald-AI/tweakcc

  Summary:
    * Customize Claude Code appearance: themes, thinking verbs, spinner, input box style.
    * Patch system prompts and add custom toolsets for both native and npm installations.

  Options:
    -V, --version: Output version number.
    -d, --debug: Enable debug mode.
    -v, --verbose: Enable verbose debug mode with diffs.
    -a, --apply: Apply saved customizations without interactive UI.
*/
_:
let
  TweakccModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.tweakcc.extended;
    in
    {
      options.programs.tweakcc.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable tweakcc.";
        };

        package = lib.mkPackageOption pkgs "tweakcc" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.tweakcc = TweakccModule;
}
