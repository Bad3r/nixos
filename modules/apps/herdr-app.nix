/*
  Package: herdr-app
  Description: Herdr desktop app for terminals and coding agents.
  Homepage: https://github.com/herdrdev/herdr-app
  Documentation: https://github.com/herdrdev/herdr-app/tree/main/docs
  Repository: https://github.com/herdrdev/herdr-app

  Notes:
    * Upload, feedback, update, and release-note media requests run only in release builds (`HERDR_APP_RELEASE`); this is a source build.
    * The launcher sets HERDR_TELEMETRY=0, which stops local usage collection and deletes its stored id and counts.
    * The package wrapper appends its bundled herdr-core to PATH, so the app never runs the core installer.
    * User-written mods can still load images and run commands.
*/
{ inputs, ... }:
{
  flake.nixosModules.apps.herdr-app =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.herdr-app.extended;
      upstream = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.herdr-app;
    in
    {
      options.programs.herdr-app.extended = {
        enable = lib.mkEnableOption "the Herdr desktop app";
        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.symlinkJoin {
            name = "herdr-app-${upstream.version}";
            inherit (upstream) version meta;
            paths = [ upstream ];
            nativeBuildInputs = [ pkgs.makeWrapper ];
            postBuild = ''
              wrapProgram "$out/bin/herdr-app" --set HERDR_TELEMETRY 0
            '';
          };
          defaultText = lib.literalExpression "privacy-wrapped inputs.llm-agents.packages.\${system}.herdr-app";
          description = "The Herdr desktop app package to use, wrapped by default to disable usage collection.";
        };
      };
      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
}
