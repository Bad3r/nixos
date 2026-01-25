/*
  Package: docker-compose
  Description: Docker CLI plugin to define and run multi-container applications with Docker.
  Homepage: https://github.com/docker/compose
  Documentation: https://docs.docker.com/compose/
  Repository: https://github.com/docker/compose

  Summary:
    * Uses declarative YAML files to orchestrate multi-service Docker stacks with shared networks, volumes, and lifecycle commands.
    * Provides `docker compose` and legacy `docker-compose` entry points for build, deploy, logs, and scaling workflows.

  Options:
    --profile <name>: Enable or disable service profiles when running compose commands.
    --project-name <name>: Override the default project name derived from the working directory.
    --env-file <file>: Load environment variables from a specific file instead of `.env`.
    --progress plain: Switch build output to plain text for CI environments.

  Example Usage:
    * `docker-compose up -d` -- Launch the defined services in detached mode.
    * `docker-compose exec db psql -U postgres` -- Open a database shell inside the `db` container.
    * `docker-compose down --volumes --remove-orphans` -- Tear down the stack and associated ephemeral resources.
*/

{
  flake.homeManagerModules.apps.docker-compose =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.docker-compose.extended;
    in
    {
      options.programs.docker-compose.extended = {
        enable = lib.mkEnableOption "Docker CLI plugin to define and run multi-container applications with Docker.";
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.docker-compose ];
      };
    };
}
