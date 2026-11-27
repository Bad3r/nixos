/*
  Package: herdr-core
  Description: Terminals for coding agents that keep running.
  Homepage: https://github.com/herdrdev/herdr-core
  Documentation: https://github.com/herdrdev/herdr-core/tree/main/docs
  Repository: https://github.com/herdrdev/herdr-core

  Notes:
    * No telemetry; only `hc update` and remote machine installs contact releases.herdr.dev.
    * Each core start asks logind for linger, which the polkit policy refuses.
*/
{ inputs, ... }:
{
  flake.nixosModules.apps.herdr-core =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.herdr-core.extended;
    in
    {
      options.programs.herdr-core.extended = {
        enable = lib.mkEnableOption "the herdr-core terminal server and its hc command";
        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.herdr-core;
          defaultText = lib.literalExpression "inputs.llm-agents.packages.\${system}.herdr-core";
          description = "The herdr-core package to use.";
        };
      };
      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
}
