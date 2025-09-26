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
    docker-compose up: Build, (re)create, start, and attach to the containers for a service.
    docker-compose down: Stop containers and remove networks, images, and volumes based on flags.
    docker-compose logs --follow: Tail service logs with stream multiplexing.
    docker-compose exec <service> <cmd>: Run a one-off command in a running service container.
    docker-compose config --services: Print validated compose services or the entire merged configuration.

  Example Usage:
    * `docker-compose up -d` — Launch the defined services in detached mode.
    * `docker-compose exec db psql -U postgres` — Open a database shell inside the `db` container.
    * `docker-compose down --volumes --remove-orphans` — Tear down the stack and associated ephemeral resources.
*/

{
  flake.homeManagerModules.apps.docker-compose =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.docker-compose ];
    };
}
